package io.devopsnexus.nexusapp;

import java.util.Map;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.config.inject.ConfigProperty;

@ApplicationScoped
@Path("/info")
public class InfoResource {

    @Inject
    @ConfigProperty(name = "app.version", defaultValue = "1.0.0")
    private String appVersion;

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, String> info() {
        return Map.of(
            "app", "NexusLiberty",
            "description", "Enterprise Middleware Modernization Platform",
            "version", appVersion,
            "runtime", System.getProperty("java.runtime.name", "Unknown"),
            "javaVersion", System.getProperty("java.version", "Unknown")
        );
    }
}
// CI/CD pipeline test
