## Demo Workload - Log4j



This workload is a apache webserer running with CVE CVE-2021-42013
The container is build to run as root and it is binding the default http port 80
Usually developers will run it as privileged but it will fail on OCP because of the serviceaccount privileges, so someone had binding the SA to cluster-admin to make the
workload run, probably because of lack of SCC skills. 

which brings a big problem, it is easy to take access to the token and cause problems to the cluster

so, easy fix it is to block privileged containers and use the proper SSC - anyuid, it is not ideal but it will mitigate few problems.


Shiftleft - Make sure to run the container as non-root and change the binding port from 80 to 8080 - try exploit.. 
container is still vulnerable but it is better than before..!

Security profile operator - using seccomps to mitigate other cmds to be executed.


-------
### Vulnerability Management

5 Images with log4j in it! 

show the dashboard and pich one deployment at risk - E.G report-generator 

In case of demo the search capabilities: 

Search for CVE CVE-2021-44228

Pick one Image, explain the image view, open the log4j CVE and show that other images running does have the same issue. Jump to RISK!

----------
RISK 

Show all the vulnerabilities detected, policy violations, explain process baselines, how it works, also networking baseline and how simple is to create network policies..
----------

### Violations

Explain what is violation - Prepare for the demo 001 - Getting kubernetes Token - cluster-admin access.. 
With the token we can now attack visa-processor and get its ENV
#Game Over.

Run the demo and start to explain the runtime activities, we can use the search option to limit by day and time of the violation.

02/20/2023 09:00:00 AM UTC

# Demo 002 - Lateral movement - Without Network Policies

From Asset to Visa - Run some commands, install netcat and reverse shell ( in this case send info to webhook env ) 



