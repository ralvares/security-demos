FROM registry.access.redhat.com/ubi9/ubi as builder
ENV version="2.4.50"
RUN  dnf install make gcc perl wget pcre-devel expat-devel -y && \
    wget https://archive.apache.org/dist/httpd/httpd-${version}.tar.gz && \
    tar -xf httpd-${version}.tar.gz && \
    wget https://dlcdn.apache.org//apr/apr-1.7.2.tar.gz && \
    tar xzvf apr-1.7.2.tar.gz -C httpd-${version}/srclib/ && \
    wget https://dlcdn.apache.org//apr/apr-util-1.6.3.tar.gz && \
    tar xzvf apr-util-1.6.3.tar.gz -C httpd-${version}/srclib/ && \
    mv /httpd-${version}/srclib/apr-1.7.2/ /httpd-${version}/srclib/apr && \
    mv /httpd-${version}/srclib/apr-util-1.6.3/ /httpd-${version}/srclib/apr-util && \
    ./httpd-${version}/configure && \
    make && make install

ADD httpd.conf /usr/local/apache2/conf/httpd.conf

FROM registry.access.redhat.com/ubi9/ubi-minimal

COPY --from=builder /usr/local/apache2 /usr/local/apache2

RUN microdnf update -y && microdnf upgrade -y && microdnf install expat -y && rpm -e --nodeps $(rpm -qa '*rpm*' '*dnf*' '*libsolv*' '*hawkey*' 'yum*')

EXPOSE 8080

USER 1001

ENTRYPOINT ["/usr/local/apache2/bin/httpd", "-D", "FOREGROUND"]