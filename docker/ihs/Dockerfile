# =============================================================================
# Containerized IHS (IBM HTTP Server stand-in)
# Uses Apache HTTPD with mod_proxy_balancer to replicate the WAS plugin
# load-balancing pattern in a containerized OKD environment.
# =============================================================================
FROM httpd:2.4-alpine

# Remove default config and replace with our LB config
RUN rm -f /usr/local/apache2/conf/httpd.conf
COPY docker/ihs/httpd.conf /usr/local/apache2/conf/httpd.conf

# Non-root: listen on 8080 instead of 80
RUN sed -i 's/^#LoadModule rewrite_module/LoadModule rewrite_module/' \
    /usr/local/apache2/conf/httpd.conf || true

EXPOSE 8080
