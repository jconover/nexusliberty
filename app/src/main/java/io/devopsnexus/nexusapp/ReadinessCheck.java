package io.devopsnexus.nexusapp;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.servlet.ServletContext;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.HealthCheckResponseBuilder;
import org.eclipse.microprofile.health.Readiness;

@Readiness
@ApplicationScoped
public class ReadinessCheck implements HealthCheck {

    @Inject
    private ServletContext servletContext;

    @Override
    public HealthCheckResponse call() {
        HealthCheckResponseBuilder builder = HealthCheckResponse.named("nexusliberty-readiness");

        if (servletContext != null && servletContext.getContextPath() != null) {
            builder.up()
                   .withData("contextPath", servletContext.getContextPath());
        } else {
            builder.down()
                   .withData("reason", "ServletContext not available");
        }

        return builder.build();
    }
}
