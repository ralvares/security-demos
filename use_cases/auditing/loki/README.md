{job="audit-logs"} 
  |= "403" 
  | json ip="sourceIPs[0]", user="user.username", resource="objectRef.resource"
  | ip != "" 
  | user !~ ".*openshift.*|.*kube-.*"
  | line_format "IP: {{.ip}} | USER: {{.user}} | RESOURCE: {{.resource}}"

  