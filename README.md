# aws-bluegreen-deployment
Shell script to do blue green deployment in AWS

### Script output for fresh deployment:

root@VirtualBox:~/bgdeploy$ ./bluegreendeployment.sh  
Existing instances:  
Newly created instances: i-0ea7a5252cf6db4d1 i-0e8f5411dfb7c15d4 i-0ca0db54c421d1cf6 i-060c6b9c8df2ccbf4  
Waiting for new instances to be in running state...Done  
New instances are registered in Application Load Balancer  
Waiting for new instances to be in healthy state...................Done  

### Script output for existing deployment:

root@VirtualBox:~/bgdeploy$ ./bluegreendeployment.sh   
Existing instances: i-0e8f5411dfb7c15d4 i-0ea7a5252cf6db4d1 i-060c6b9c8df2ccbf4 i-0ca0db54c421d1cf6  
Newly created instances: i-080cf05188f92d86c i-06ad3579b7ff09199 i-0f63e9c55f6f9c64a i-0e7525a5ec1d11b85  
Waiting for new instances to be in running state...Done  
New instances are registered in Application Load Balancer  
Waiting for new instances to be in healthy state.................................Done  
Deregistered the old instances from Application Load Balancer  
Waiting for all inflight requests to old instances to be completed.............................................Done  
Terminated the old instances  
