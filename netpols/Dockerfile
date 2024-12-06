FROM registry.access.redhat.com/ubi8/python-38
USER root

RUN yum update -y
RUN yum upgrade -y
RUN curl https://mirror.openshift.com/pub/rhacs/assets/3.74.0/bin/Linux/roxctl --output /bin/roxctl && \
    chmod +x /bin/roxctl && \
    curl -L https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.0.0/kustomize_v5.0.0_linux_amd64.tar.gz -o - | tar xzvf - -C /bin && chmod +x /bin/kustomize && \
    dnf update -y && dnf install graphviz -y && \
    pip install network-config-analyzer && pip install requests 

COPY get_netpol.py /usr/local/bin
