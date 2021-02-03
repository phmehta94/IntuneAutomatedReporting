# Intune Automated Reporting
Azure Automation runbook scripts to grab Intune data and output CSV to Storage Account containers.

## Set up

Setting up the runbook scripts to automatically grab Intune data ouput CSVs to Azure blob storage accounts can be done in six simple steps.

1. Graph API Registration
1. Create a Resource Group
1. Create a Storage Account
1. Create an Automation Account
1. Set up Automation Runbooks
1. Import data into PowerBI

Check out the step-by-step guide to learn more.

## Create effective visuals in PowerBI

### Applications

This visual uses the following scripts.
* **AppInstallStates.ps1**
* **ServicingRings.ps1**

![Applications visualization](/images/appsbydepartment.png)

### Servicing

This following visuals use the **ServicingRings.ps1** script.

![Servicing visualization](/images/servicingoverview.png)

<br><br>

![Historical servicing visualization](/images/historicalservicingcomparison.png)

