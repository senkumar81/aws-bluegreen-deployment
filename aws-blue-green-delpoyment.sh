#!/bin/bash
####################
# AWS resources used
####################

# Amazon Resource Name (ARN) of the target group
target_group_arn="arn:aws:elasticloadbalancing:us-east-1:xxxxxxxxxxxxxxx:targetgroup/xxxxxxxxxxxxxxx/xxxxxxxxxxxxxxxx"

# User data (or) start up script that should run when an instance is launched
user_data_file_name="user_data.sh"

# Name of the key pair
key_pair_name="xxxxxxxx"

# ID of the AMI
image_id="ami-xxxxxxxx"

# Subnet IDs to launch the instances. Multiple IDs can be specified and should be separated by space
subnet_ids="subnet-xxxxxxxx1 subnet-xxxxxxxx2"

# ID of the security group
security_group_id="sg-xxxxxxxx"

# Instance type
instance_type="t2.small"

# Instance port. Newly created instances are registered in the given target group using this port
instance_port=5080

# No of EC2 instances to be launched in each given subnet
instance_count=1

# IAM instance profile. More info on https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_use_switch-role-ec2.html
ec2_iam_role_name="test-ec2-role"



# Time to wait for the instances in Application Load Balancer to become healthy
healthy_state_timeout_sec=300 

# Time to wait for the newly created instances to be in running state
running_state_timout_sec=120 

# Time to wait for the connection draining to complete
connection_draining_timeout_sec=300 

# Time interval to check the instance states like running, healthy etc
polling_interval_sec=5 



checkStatus()
{
   given_state=$1
   shift
   arr=("$@")
   for state in "${arr[@]}"
   do
       if [ "${state}" != "${given_state}" ]
       then
           return 1
       fi
   done
   return 0;
}

############################
# Existing Green environment
############################

existing_instance_id_arr=($(aws elbv2 describe-target-health --target-group-arn ${target_group_arn} --output text --query 'TargetHealthDescriptions[*].Target.Id'))

echo "Existing instances: ${existing_instance_id_arr[@]}"

#########################
# Create Blue environment
#########################

instance_id_arr=()
subnet_id_arr=($subnet_ids)
for subnet_id in "${subnet_id_arr[@]}"
do
   instance_id_arr+=($(aws ec2 run-instances --count ${instance_count} --image-id ${image_id} --user-data file://${user_data_file_name} --iam-instance-profile Name=${ec2_iam_role_name} --instance-type ${instance_type} --key-name "${key_pair_name}" --security-group-ids ${security_group_id} --subnet-id ${subnet_id} --output text --query 'Instances[*].InstanceId'))
done

echo "Newly created instances: ${instance_id_arr[@]}"

###################################################
# Wait for the new instances to be in running state
###################################################

instance_running=false
echo -n "Waiting for new instances to be in running state"
for ((i=1;i<=running_state_timout_sec;i++))
do
   instance_state_arr=($(aws ec2 describe-instances --instance-ids ${instance_id_arr[@]} --output text --query 'Reservations[*].Instances[*].State.Name'))
   if checkStatus "running" ${instance_state_arr[@]}; 
   then
      instance_running=true
      break
   fi
   sleep ${polling_interval_sec}
   echo -n '.'
done

if [ $instance_running = true ]
then
   echo -n "Done"
else
   echo -n "Failed"
   exit 1
fi

#########################################################
# Register the new instances in Application Load Balancer
#########################################################

target_id_arr=()
for instance_id in "${instance_id_arr[@]}"
do
   target_id_arr+=("Id=${instance_id},Port=${instance_port}")   
done

aws elbv2 register-targets --target-group-arn ${target_group_arn} --targets ${target_id_arr[@]}

echo -e "\nNew instances are registered in Application Load Balancer"

###################################################
# Wait for the new instances to be in healthy state
###################################################

instance_healthy=false
echo -n "Waiting for new instances to be in healthy state"
for ((i=1;i<=healthy_state_timeout_sec;i++))
do
   instance_health_state_arr=($(aws elbv2 describe-target-health --target-group-arn ${target_group_arn} --targets ${target_id_arr[@]} --output text --query 'TargetHealthDescriptions[*].TargetHealth.State'))
   if checkStatus "healthy" ${instance_health_state_arr[@]};
   then
      instance_healthy=true
      break
   fi
   sleep ${polling_interval_sec}
   echo -n '.'
done

##################################################################################################
# Deregister and terminate the old instances in ALB once the new instances are running and healthy
##################################################################################################

if [ $instance_healthy = true ]
then
   echo -n "Done"

   if [ ${#existing_instance_id_arr[@]} -gt 0 ]
   then

      # Deregistering the old instances
      target_id_arr=()
      for existing_instance_id in "${existing_instance_id_arr[@]}"
      do
         target_id_arr+=("Id=${existing_instance_id},Port=${instance_port}")  
      done
      aws elbv2 deregister-targets --target-group-arn ${target_group_arn} --targets ${target_id_arr[@]}
      echo -e "\nDeregistered the old instances from Application Load Balancer"

      # Connection Draining for old instances 
      echo -n "Waiting for all inflight requests to old instances to be completed"
      for ((i=1;i<=connection_draining_timeout_sec;i++))
      do
         old_instance_state_arr=($(aws elbv2 describe-target-health --target-group-arn ${target_group_arn} --targets ${target_id_arr[@]} --output text --query 'TargetHealthDescriptions[*].TargetHealth.State'))
         if checkStatus "unused" ${old_instance_state_arr[@]};
         then
            echo -n "Done"

            # Terminating the old instances
            aws ec2 terminate-instances --instance-ids ${existing_instance_id_arr[@]} > /dev/null
            echo -e "\nTerminated the old instances"
            break
         fi
         sleep ${polling_interval_sec}
         echo -n '.'
      done
   fi
else
   echo -e "\nNewly added instances are not healthy"

   # Terminating the new instances
   aws ec2 terminate-instances --instance-ids ${instance_id_arr[@]} > /dev/null
   echo -e "\nTerminated the new instances"
fi
