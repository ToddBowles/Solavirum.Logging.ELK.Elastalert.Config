[CmdletBinding()]
param
(
    [switch]$deploy,
    [string]$octopusServerUrl,
    [string]$octopusApiKey,
    [string]$commaSeparatedDeploymentEnvironments,
	[string[]]$projects,
    [int]$buildNumber,
    [switch]$prerelease,
    [string]$prereleaseTag
)

$error.Clear();

$ErrorActionPreference = "Stop";

$here = Split-Path $script:MyInvocation.MyCommand.Path;

. "$here\_Find-RootDirectory.ps1";

$rootDirectory = Find-RootDirectory $here;
$rootDirectoryPath = $rootDirectory.FullName;

. "$rootDirectoryPath\scripts\common\Functions-Build.ps1";

$arguments = @{};
$arguments.Add("Deploy", $deploy);
$arguments.Add("CommaSeparatedDeploymentEnvironments", $commaSeparatedDeploymentEnvironments);
$arguments.Add("OctopusServerUrl", $octopusServerUrl);
$arguments.Add("OctopusServerApiKey", $octopusApiKey);
$arguments.Add("Projects", $projects);
$arguments.Add("VersionStrategy", "SemVerWithPatchFilledAutomaticallyWithBuildNumber");
$arguments.Add("buildNumber", $buildNumber);
$arguments.Add("Prerelease", $prerelease);
$arguments.Add("PrereleaseTag", $prereleaseTag);
$arguments.Add("BuildEngineName", "nuget");

Build-DeployableComponent @arguments