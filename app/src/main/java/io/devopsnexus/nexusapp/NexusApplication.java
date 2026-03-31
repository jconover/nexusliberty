package io.devopsnexus.nexusapp;

import jakarta.ws.rs.ApplicationPath;
import jakarta.ws.rs.core.Application;
import org.eclipse.microprofile.openapi.annotations.OpenAPIDefinition;
import org.eclipse.microprofile.openapi.annotations.info.Info;

@ApplicationPath("/api")
@OpenAPIDefinition(
    info = @Info(
        title = "NexusLiberty API",
        version = "1.0.0",
        description = "Enterprise Middleware Modernization Platform REST API"
    )
)
public class NexusApplication extends Application {
}
