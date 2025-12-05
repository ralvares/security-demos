# ------------------------------------------
# 1. Builder: Compile and package as RPM
# ------------------------------------------
FROM registry.access.redhat.com/ubi9/ubi AS builder
ENV VERSION="2.4.50"

RUN dnf install -y \
      rpm-build rpmdevtools redhat-rpm-config \
      gcc make perl wget \
      pcre-devel expat-devel apr-devel apr-util-devel openssl-devel && \
    rpmdev-setuptree

COPY httpd.conf /root/rpmbuild/SOURCES/httpd.conf

WORKDIR /root/rpmbuild/SOURCES

RUN wget https://archive.apache.org/dist/httpd/httpd-${VERSION}.tar.gz && \
    wget https://archive.apache.org/dist/apr/apr-1.7.4.tar.gz && \
    wget https://archive.apache.org/dist/apr/apr-util-1.6.3.tar.gz

WORKDIR /root/rpmbuild/SPECS
COPY httpd-custom.spec .

WORKDIR /root
RUN rpmbuild -bb rpmbuild/SPECS/httpd-custom.spec

# ------------------------------------------
# 2. Runtime: Minimal UBI + custom httpd RPM
# ------------------------------------------
FROM registry.access.redhat.com/ubi9/ubi-minimal

COPY --from=builder /root/rpmbuild/RPMS/ /tmp/rpms/

RUN microdnf install -y mailcap perl expat openssl pcre && \
    ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64) RPM_PATH=$(ls /tmp/rpms/x86_64/ | grep "httpd-2.4.50-1.*.rpm") ;; \
      aarch64) RPM_PATH=$(ls /tmp/rpms/aarch64/ | grep "httpd-2.4.50-1.*.rpm") ;; \
      *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
    esac && \
    rpm -ivh /tmp/rpms/$ARCH/$RPM_PATH && \
    microdnf clean all && \
    rm -rf /var/cache/{dnf,yum} /tmp/rpms && \
    rpm -e --nodeps $(rpm -qa '*rpm*' '*dnf*' '*libsolv*' '*hawkey*' 'yum*') || true

RUN mkdir -p /var/www/html /var/www/cgi-bin /var/log/httpd /run/httpd && \
    chown -R 1001:0 /var/www /var/log/httpd /run/httpd && \
    chmod -R g+rwX /var/www /var/log/httpd /run/httpd

EXPOSE 8080
USER 1001
ENTRYPOINT ["/usr/sbin/httpd", "-DFOREGROUND"]
