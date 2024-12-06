Network policies can be very difficult to create correctly because even a small mistake in the configuration can have a big impact on connectivity. For example, if you add an extra dash to the configuration, it can allow all connections instead of just the ones you want.

```
git clone https://github.com/ralvares/security-demos
cd security-demos/manifests
roxctl generate netpol . | sed 's/port: 53/port: 5353/' | oc apply -f -
```

# Generating network policies using the acs baseline from the pipeline