package io.devopsnexus.nexusapp;

import java.lang.management.ManagementFactory;
import java.lang.management.MemoryMXBean;
import java.lang.management.ThreadMXBean;

import jakarta.enterprise.context.ApplicationScoped;
import org.eclipse.microprofile.health.HealthCheck;
import org.eclipse.microprofile.health.HealthCheckResponse;
import org.eclipse.microprofile.health.HealthCheckResponseBuilder;
import org.eclipse.microprofile.health.Liveness;

@Liveness
@ApplicationScoped
public class LivenessCheck implements HealthCheck {

    private static final double HEAP_USAGE_THRESHOLD = 0.95;

    @Override
    public HealthCheckResponse call() {
        ThreadMXBean threadBean = ManagementFactory.getThreadMXBean();
        MemoryMXBean memoryBean = ManagementFactory.getMemoryMXBean();

        long[] deadlockedThreads = threadBean.findDeadlockedThreads();
        long usedHeap = memoryBean.getHeapMemoryUsage().getUsed();
        long maxHeap = memoryBean.getHeapMemoryUsage().getMax();
        double heapRatio = maxHeap > 0 ? (double) usedHeap / maxHeap : 0;

        HealthCheckResponseBuilder builder = HealthCheckResponse.named("nexusliberty-liveness");

        boolean noDeadlocks = deadlockedThreads == null;
        boolean heapOk = heapRatio < HEAP_USAGE_THRESHOLD;

        if (noDeadlocks && heapOk) {
            builder.up()
                   .withData("threadCount", threadBean.getThreadCount())
                   .withData("heapUsedMB", usedHeap / (1024 * 1024))
                   .withData("heapMaxMB", maxHeap / (1024 * 1024))
                   .withData("heapUsagePercent", String.format("%.1f", heapRatio * 100));
        } else {
            builder.down();
            if (!noDeadlocks) {
                builder.withData("deadlockedThreads", deadlockedThreads.length);
            }
            if (!heapOk) {
                builder.withData("heapUsagePercent", String.format("%.1f", heapRatio * 100))
                       .withData("reason", "Heap usage exceeds " + (int)(HEAP_USAGE_THRESHOLD * 100) + "% threshold");
            }
        }

        return builder.build();
    }
}
