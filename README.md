![](https://github.com/massilp/aws-rover/workflows/master/badge.svg)
![](https://github.com/massilp/aws-rover/workflows/.github/workflows/ci-branches.yml/badge.svg)
[![Gitter](https://badges.gitter.im/massilp/community.svg)](https://gitter.im/massilp/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

# Cloud Adoption Framework for AWS - Landing zones on Terraform - Rover

The CAF **rover** is helping you managing your enterprise Terraform deployments on AWS and is composed of two parts:

- **A docker container**
  - Allows consistent developer experience on PC, Mac, Linux, including the right tools, git hooks and DevOps tools.
  - Native integration with [Visual Studio Code](https://code.visualstudio.com/docs/remote/containers), [GitHub Codespaces](https://github.com/features/codespaces).
  - Contains the versioned toolset you need to apply landing zones.
  - Helps you switching components versions fast by separating the run environment and the configuration environment.
  - Ensure pipeline ubiquity and abstraction run the rover everywhere, whichever pipeline technology.

- **A Terraform wrapper**
  - Helps you store and retrieve Terraform state files on AWS S3 Bucket.
  - Facilitates the transition to CI/CD.
  - Enables seamless experience (state connection, execution traces, etc.) locally and inside pipelines.

The rover is available from the Docker Hub in form of:

- [Standalone edition](https://hub.docker.com/r/massilp/aws-rover/tags?page=1&ordering=last_updated): to be used for landing zones engineering or pipelines.


## Community

Feel free to open an issue for feature or bug, or to submit a PR.

In case you have any question, you can reach out to tf-landingzones at microsoft dot com.

You can also reach us on [Gitter](https://gitter.im/massilp/community?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge)

## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.
