# =============================================================================
# Containerized IHS (IBM HTTP Server stand-in)
# Uses Apache HTTPD with mod_proxy_balancer to replicate the WAS plugin
# load-balancing pattern in a containerized OKD environment.
# =============================================================================
FROM httpd:2.4-alpine

# Remove default config and replace with our LB config
RUN rm -f /usr/local/apache2/conf/httpd.conf
COPY docker/ihs/httpd.conf /usr/local/apache2/conf/httpd.conf

# Ensure non-root user can write logs and pid file
RUN chown -R 1001:0 /usr/local/apache2/logs && \
    chmod -R g=u /usr/local/apache2/logs

EXPOSE 8080

USER 1001
