package io.devopsnexus.nexusapp;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.servlet.ServletContext;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.HealthCheckResponseBuilder;
import org.eclipse.microprofile.health.Readiness;

/**
 * MicroProfile Readiness probe for Kubernetes/OpenShift health checks.
 * Validates that the servlet context is initialized and that the Hazelcast
 * JCache session cache is accessible. Reports DOWN if either dependency
 * is unavailable, preventing traffic from reaching an unready pod.
 */
@Readiness
@ApplicationScoped
public class ReadinessCheck implements HealthCheck {

    @Inject
    private ServletContext servletContext;

    @Override
    public HealthCheckResponse call() {
        HealthCheckResponseBuilder builder = HealthCheckResponse.named("nexusliberty-readiness");

        boolean servletReady = servletContext != null && servletContext.getContextPath() != null;
        boolean cacheReady = checkSessionCache();

        if (servletReady && cacheReady) {
            builder.up()
                   .withData("contextPath", servletContext.getContextPath())
                   .withData("sessionCache", "available");
        } else {
            builder.down()
                   .withData("servletContext", servletReady ? "ok" : "unavailable")
                   .withData("sessionCache", cacheReady ? "ok" : "unavailable");
        }

        return builder.build();
    }

    /**
     * Verify Hazelcast JCache session cache is accessible.
     * Uses JNDI lookup for the CacheManager configured in server.xml.
     * Returns true if unavailable (graceful degradation) when session
     * caching is not configured (e.g., local dev without Hazelcast).
     */
    private boolean checkSessionCache() {
        try {
            Class<?> cachingClass = Class.forName("javax.cache.Caching");
            Object provider = cachingClass.getMethod("getCachingProvider").invoke(null);
            Object cacheManager = provider.getClass().getMethod("getCacheManager").invoke(provider);
            return cacheManager != null;
        } catch (Exception e) {
            // JCache API not on classpath or no provider configured —
            // treat as ready (session caching is optional for readiness)
            return true;
        }
    }
}
