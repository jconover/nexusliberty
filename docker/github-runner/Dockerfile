# GitHub Actions self-hosted runner for NexusLiberty CI/CD.
# Extends the official actions-runner base image with the OpenShift CLI (oc)
# so that workflows can trigger Tekton PipelineRuns on OKD 4.x.

FROM ghcr.io/actions/actions-runner:latest

USER root

# Install oc and kubectl from the official OpenShift mirror (stable-4.16 channel).
RUN curl -fsSL \
      https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.16/openshift-client-linux.tar.gz \
    | tar -xz -C /usr/local/bin oc kubectl \
 && chmod +x /usr/local/bin/oc /usr/local/bin/kubectl

USER runner
