package io.devopsnexus.nexusapp;

import java.util.Map;

import jakarta.enterprise.context.ApplicationScoped;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;

@ApplicationScoped
@Path("/info")
public class InfoResource {

    @GET
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, String> info() {
        return Map.of(
            "app", "NexusLiberty",
            "description", "Enterprise Middleware Modernization Platform",
            "version", "1.0.0",
            "runtime", System.getProperty("java.runtime.name", "Unknown"),
            "javaVersion", System.getProperty("java.version", "Unknown")
        );
    }
}
