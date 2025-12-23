## Playing with the API 

The Shell Script is designed to retrieve information about a Kubernetes deployment and its associated containers using the RHACS/Stackrox API.
One of the key advantages of using the API to retrieve information is that it can be significantly faster than using a GUI. This is because the API allows you to retrieve large amounts of data in a single request, which can be more efficient than manually clicking through a GUI to access the same information.

Another advantage of using the API is that it can provide more detailed information than the GUI. While the GUI may provide a high-level overview of your cluster, the API allows you to access detailed metadata about each deployment and its associated containers. This metadata can be useful for identifying suspicious activity and investigating potential security incidents.

The script is able to retrieve a detailed history of all the processes that have run on the deployment and its containers, which can be useful for investigating any suspicious activity.This information include details such as the container name, ID, time, arguments, and other metadata.

Once the script has retrieved this information, it likely groups the container information by deployment and generates a report that summarizes the activity for each deployment. This report might include information such as the number of times each container has been executed, the arguments that were passed to the container, and any other relevant metadata.

By analyzing this json, digital forensics investigators can identify any anomalies or suspicious activity that may have occurred on the deployment.

Overall, the shell script is just a simple useful example for investigating potential security incidents on Kubernetes deployments, and can help digital forensics investigators quickly identify suspicious activity and take appropriate action to mitigate any potential threats.

## Running the script

Make sure that you have the deployment baseline locked ( faster testing ) and run anything that is not part of the baseline and run the follow script.

```
export ROX_ENDPOINT=central-stackrox.apps.ocp.cluster.local:443   
export ROX_API_TOKEN=$(cat ~/token)

./dump_deployment_foresics.sh visa-processor | jq -r '.groups[] | select(.suspicious == true) | .containerName as $cn | .groups[].signals[] | [$cn, .signal.containerId, .signal.time, .signal.name, .args, .signal.execFilePath, .signal.pid, .signal.uid, .signal.gid, .signal.suspicious] | @csv'

"visa-processor","6ffaf8320fd5","2023-03-07T15:22:10.532511247Z","nc",,"/bin/nc",2281831,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:14.686433591Z","nc",,"/bin/nc",2281933,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.671267012Z","rm",,"/bin/rm",2281637,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.927284881Z","rm",,"/bin/rm",2281823,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.585546502Z","rm",,"/bin/rm",2281629,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:21:51.564149312Z","sh",,"/bin/sh",2281380,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.659524059Z","sh",,"/bin/sh",2281757,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:21:51.562813613Z","sh",,"/bin/sh",2281374,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.548920799Z","tar",,"/bin/tar",2281625,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.655302862Z","ldconfig",,"/sbin/ldconfig",2281634,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.925877270Z","sh",,"/usr/bin/apt",2281822,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:06.721818211Z","apt",,"/usr/bin/apt",2281734,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:21:58.504837716Z","apt",,"/usr/bin/apt",2281494,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.773364675Z","dpkg",,"/usr/bin/dpkg",2281785,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:06.727271550Z","dpkg",,"/usr/bin/dpkg",2281735,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.894919471Z","dpkg",,"/usr/bin/dpkg",2281818,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.266976855Z","dpkg",,"/usr/bin/dpkg",2281578,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.269376668Z","dpkg-deb",,"/usr/bin/dpkg-deb",2281581,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.377694553Z","dpkg-deb",,"/usr/bin/dpkg-deb",2281598,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.415078393Z","dpkg-deb",,"/usr/bin/dpkg-deb",2281607,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.306600214Z","dpkg-deb",,"/usr/bin/dpkg-deb",2281582,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.559447539Z","dpkg-deb",,"/usr/bin/dpkg-deb",2281626,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.440897999Z","dpkg-deb",,"/usr/bin/dpkg-deb",2281616,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.365457865Z","dpkg-split",,"/usr/bin/dpkg-split",2281593,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.397947318Z","dpkg-split",,"/usr/bin/dpkg-split",2281602,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.265500643Z","dpkg-split",,"/usr/bin/dpkg-split",2281577,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.542658461Z","dpkg-split",,"/usr/bin/dpkg-split",2281621,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.428208471Z","dpkg-split",,"/usr/bin/dpkg-split",2281611,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.906822432Z","update-alternat",,"/usr/bin/update-alternatives",2281820,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.569193847Z","http",,"/usr/lib/apt/methods/http",2281756,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.660684514Z","dpkg-preconfigu",,"/usr/sbin/dpkg-preconfigure",2281758,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:01.654199828Z","libc-bin.postin",,"/var/lib/dpkg/info/libc-bin.postinst",2281633,0,0,
"visa-processor","6ffaf8320fd5","2023-03-07T15:22:08.905197937Z","netcat-traditio",,"/var/lib/dpkg/info/netcat-traditional.postinst",2281819,0,0,
```

The jq command provided will only output the entries where the suspicious field is true, The output will have the following fields in order: container name, container ID, time, name, args, execFilePath, pid, uid, gid.

# Generating network policies using the acs baseline from the pipeline

