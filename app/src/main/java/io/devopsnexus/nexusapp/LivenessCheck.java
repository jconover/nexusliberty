package io.devopsnexus.nexusapp;

import java.lang.management.ManagementFactory;
import java.lang.management.ThreadMXBean;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.HealthCheckResponseBuilder;
import org.eclipse.microprofile.health.Liveness;

@Liveness
@ApplicationScoped
public class LivenessCheck implements HealthCheck {

    @Override
    public HealthCheckResponse call() {
        ThreadMXBean threadBean = ManagementFactory.getThreadMXBean();
        long[] deadlockedThreads = threadBean.findDeadlockedThreads();
        HealthCheckResponseBuilder builder = HealthCheckResponse.named("nexusliberty-liveness");

        if (deadlockedThreads == null) {
            builder.up()
                   .withData("threadCount", threadBean.getThreadCount());
        } else {
            builder.down()
                   .withData("deadlockedThreads", deadlockedThreads.length);
        }

        return builder.build();
    }
}
