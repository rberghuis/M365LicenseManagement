#Requires -Version 3

<#
.SYNOPSIS
This script provides the capability to validate Group Based Licensing, to catch whenever Microsoft auto-adds/enables a new Plan within a Sku.

.DESCRIPTION
Requires an input file that lists the Entra ID Groups by Object ID (GUID), License (skuId) and Enabled Plans (servicePlanId).
Optionally, you can define the Enabled Plans as '*' (wildcard) to state that all plans should be enabled without the need of listing all individual ones

Licenses assigned to a group list the Assigned License (skuID) and a list of Disabled Plans (servicePlanId).
The code will retrieve the available Licenses from the tenant (subscribedSku) to faciltiate building a list of available Service Plans.
The expected list of Disabled Plans is whatever the License (sku) provides without the list of Enabled Plans from the input file.
When the EnabledPlans is marked as a '*' (wildcard), then the list of DisabledPlans will default to 'an empty list'

It will subsequently determine (in order):
- If the expected License SKU is assigned
- If the expected disabled service plans are indeed disabled
- If the expected enabled service plans are indeed NOT disabled

Within Microsoft Entra ID, when assigning the same license the same group, the license is consolidated into 1 and the enabled/disabled plans are combined.
Additional logic is included to avoid end-user introduced issues (PEKBAC) in the input-file with regards to specifying the same License (sku) on the same group (GUID) multiple times with same or different Enabled Plans (servicePlanId).

Copyright (c) 2024 Robbert Berghuis | https://www.linkedin.com/in/robbertberghuis

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The use of the third-party software links on this website is done at your own discretion and risk and with agreement that you will be solely responsible for any damage to your computer system or loss of data that results from such activities. You are solely responsible for adequate protection and backup of the data and equipment used in connection with any of the software linked to this website, and we will not be liable for any damages that you may suffer connection with downloading, installing, using, modifying or distributing such software. No advice or information, whether oral or written, obtained by you from us or from this website shall create any warranty for the software.

.INPUTS
None

.OUTPUTS
[System.String[]]

.NOTES
Copyright (c) 2024 Robbert Berghuis | https://www.linkedin.com/in/robbertberghuis

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

The use of the third-party software links on this website is done at your own discretion and risk and with agreement that you will be solely responsible for any damage to your computer system or loss of data that results from such activities. You are solely responsible for adequate protection and backup of the data and equipment used in connection with any of the software linked to this website, and we will not be liable for any damages that you may suffer connection with downloading, installing, using, modifying or distributing such software. No advice or information, whether oral or written, obtained by you from us or from this website shall create any warranty for the software.

.LINK
https://www.linkedin.com/in/robbertberghuis
https://github.com/rberghuis/M365LicenseManagement
https://opensource.org/license/mit
#>

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

# Read input file
Try {
    <# List of GroupGUID with the expected license based on SkuID and a list of EnabedPlans. The EnabledPlans are listed by ServicePlanID or contain 'all' by defining a wildcard (*).
        GroupGuid;skuId;EnabledPlans
        ca506675-9775-4469-9939-cfb5660bd15c;ee2ca20-f1a3-4bb7-9f95-4e9418ecf508;*
        ca506675-9775-4469-9939-cfb5660bd15c;5b17c832-490f-4e02-ac5d-db864f3bfc76;80d9a40e-2f02-4578-95c9-4e0f551056e9,df449e38-240d-4611-860e-9dc526d9a5b0
       This shows multiple Licenses on the same group, with 1 licensing defaulting to all available Plans and the other specifying a list of plans to be enabled
    #>
    $ExpectedLicenseDetails = Import-Csv -Delimiter ';' -Encoding UTF8 -Path ".\Test-GroupBasedLicensing-input.csv" -ErrorAction Stop
} Catch {
    Throw "Could not retrieve the expectedLicense assignment details from the input Csv"
}

#region Perform a sanity check on input file, focussing on multiple same SKU on the same group with or without same EnabledPlans
$PlaceHolderRemoval = "RemoveDuplicateEntry"
Foreach ($grp in (($ExpectedLicenseDetails | Group-Object GroupGUID).Name)) {
    # Defaulting used variables on each run
    $Group = $null
    $DuplicateSku = $null
    $DuplicateLines = $null
    $CombinedEnabledPlans = $null

    # Foreach unique GroupGUID entry in the CSV file, find all entries
    $Group = $ExpectedLicenseDetails | Where-Object { $_.GroupGUID -eq $grp }
    # For these entries, group based on SkuID and confirm if there is more than 1 entry
    $DuplicateSku = $Group | Group-Object SkuID | Where-Object { $_.Count -ge 2 }
    # If we found at least 1 Duplicate Sku in the input file
    If ($DuplicateSku) {
        # This probably happens when people add new lines to the input-file as opposed to modifying the existing EnabledPlans column of the existing line
        Foreach ($DS in $DuplicateSku) {
            # "Found a duplicate entry in the input file for GroupGUID '$($GroupGUID)' and SkuID '$($DS.Name)', combining the list of EnabledPlans"
            # Create a list of the lines that are duplicate
            $DuplicateLines = $ExpectedLicenseDetails | Where-Object { $_.SkuId -eq $DS.Name }
            # Confirm if any of the lines contains a wildcard
            If ([bool]($DuplicateLines.EnabledPlans -match '\*') -eq $true) {
                # One of the Lines contains a * (wildcard) in the EnabledPlans. Define the CombinedPlans as a single '*', no need to combine a wildcard with other enabled plans
                $CombinedEnabledPlans = '*'
            } Else {
                # Create a new list of Enabled Plans that combines the multiple lines and deduplicates the entries
                $CombinedEnabledPlans = (($DuplicateLines.EnabledPlans -Join ',').Split(',') | Foreach-Object { $_.Trim() } | Sort-Object -Unique) -Join ','
            }
            # Add a new entry to the full input list
            $ExpectedLicenseDetails += [PSCustomObject]@{
                GroupGuid = $grp
                skuID = $DS.Name
                EnabledPlans = $CombinedEnabledPlans
            }
            #region Run through the input list of the possible duplicate entries
            # First up, entries that have a different value EnabledPlans
            Foreach ($entry in ($ExpectedLicenseDetails | Where-Object { $_.GroupGUID -eq $grp -and $_.SkuID -eq $DS.Name })) {
                If ($entry.EnabledPlans -ne $CombinedEnabledPlans) {
                    # If the entry does not contian the full CombinedEnabledPlans list, then mark it as 'Duplicate'
                    $entry.EnabledPlans = $PlaceHolderRemoval
                }
            }
            # Next, entries that have the same EnabledPlans value and more than 1 entry exists
            If ((($ExpectedLicenseDetails | Where-Object { $_.GroupGUID -eq $grp -and $_.SkuID -eq $DS.Name }) | Group-Object EnabledPlans).Count -gt 1) {
                # We found duplicate entries where the end-to-end line is the same, in a While-loop we modify the all lines EXCEPT the first entry (0)
                While ((($ExpectedLicenseDetails | Where-Object { $_.GroupGUID -eq $grp -and $_.SkuID -eq $DS.Name -and $_.EnabledPlans -eq $CombinedEnabledPlans }) | Group-Object EnabledPlans).Count -ge 2) {
                    ($ExpectedLicenseDetails | Where-Object { $_.GroupGUID -eq $grp -and $_.SkuID -eq $DS.Name -and $_.EnabledPlans -eq $CombinedEnabledPlans })[1].EnabledPlans = $PlaceHolderRemoval
                }
            }
            #endregion
        }
        # Finally, let's remove all duplicate entries.
        $ExpectedLicenseDetails = $ExpectedLicenseDetails | Where-Object { $_.EnabledPlans -ne $PlaceHolderRemoval }
    }
}
#endregion

#region Fetch all licenses known in the Directory
Try {
    $DirectoryLicenses = Invoke-RestMethod -Method GET -Headers @{Authorization = "Bearer $($AccessToken)"} -Uri 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=id,skuId,skuPartNumber,prepaidUnits,consumedUnits,servicePlans' -ErrorAction Stop
} Catch {
    Throw "Could not retrieve the Directory Licenses, and as a result unable to complete"
}
#endregion

#region Foreach entry of input file, fetch the current assigned licenses and match DisabledPlans with expectation
Foreach ($ELD in $ExpectedLicenseDetails) {
    # Defaulting variables on each run
    $ConfiguredLicense = $null
    $AvailablePlans = $null
    $DisabledPlans = $null
    $Scope = $null

    Write-Host " "
    Write-Host "Working on entry for Group '$($ELD.GroupGuid)' Sku '$($ELD.SkuId)' and Enabled Plans: $($ELD.EnabledPlans)"

    # Retrieve the current assigned licenses for the group
    Try {
        # Format URI as String in single quotes to avoid the need of escaping special characters.
        $URI = 'https://graph.microsoft.com/beta/groups/{0}?$select=Id, AssignedLicenses' -f $ELD.GroupGUID
        # API call to Get the assigned licenses for the group
        $ConfiguredLicense = Invoke-RestMethod -Method GET -Headers @{Authorization = "Bearer $($AccessToken)"} -Uri $URI -ErrorAction Stop
    } Catch {
        $ConfiguredLicense = $null
        Write-Verbose "    Could not retrieve configured licenses for group $($ELD.GroupGUID)"
    }

    # Retrieve the current license plans for the license in question
    If ($ConfiguredLicense) {
        # Set the scope for the current iteration based on the Sku in question, as a group can be used to write multiple licenses
        $Scope = $ConfiguredLicense.AssignedLicenses | Where-Object {$_.skuId -eq $ELD.skuId }
        If (-Not $Scope) {
            $Scope = $null
            Write-Verbose "    Could not find the expected license on the group based on SkuID: $($ELD.skuID)"
        }

        If ($Scope) {
            # Retrieve the Available Plans from the License SKU where the license applies to a User
            Try {
                $AvailablePlans = $DirectoryLicenses.Value | Where-Object {$_.skuId -eq $scope.SkuId} | Select-Object -ExpandProperty servicePlans | Where-Object {$_.AppliesTo -contains 'User'}
            } Catch {
                Write-Verbose "    Could not list the plans that are provided by the License, so no way of telling what should be enabled or disabled"
                $AvailablePlans = $null
            }

            # Based on the Available plans and the list of Expected Enabled Plans (CSV input), the DisabledPlans can be listed
            If ($ELD.EnabledPlans -eq '*') {
                # Wilcard is defined as EnabledPlans, which means all ServicePlans are expected to be enabled
                $DisabledPlans = @()
            } Else {
                # DisabedPlans is a list of All Available Plans without the ones listed explicitly as being Enabled
                Try {
                    $DisabledPlans = $AvailablePlans.servicePlanId | Where-Object { $_ -notin $ELD.EnabledPlans.Split(',') }
                    If ($null -eq $DisabledPlans) {
                        # When there're no disabled plans, we just return an empty array
                        $DisabledPlans = @()
                    }
                } Catch {
                    Write-Verbose "   Could not create a list of DisabledPlans based on the AvailablePlans minus the ones listed as 'expected to be Enabled'"
                    $DisabledPlans = $null
                }
            }
        }

        If ($null -ne $DisabledPlans -and $null -ne $Scope -and $null -ne $AvailablePlans) {
            # Confirm if the disabled license plans match expectations
            If (($Scope.DisabledPlans.count -eq $DisabledPlans.count) -and ($DisabledPlans.count -eq 0)) {
                Write-Host "    All plans that should be enabled/disabled are as expected..."
            } ElseIf (($DisabledPlans.Count -ne 0) -and ($DisabledPlans -notin $Scope.disabledPlans)) {
                Write-Host "    Not all expected disabled plans are disabled, the following plans are active and perhaps in error: {0}" -f ((($AvailablePlans | Where-Object { $_.servicePlanId -in ($DisabledPlans | Where-Object {$_ -notin $Scope.disabledPlans}) }) | Select-Object @{Name = "output"; Expression = { "[$($_.servicePlanId)] $($_.ServicePlanName)" }}) | Select-Object -ExpandProperty output) -Join ', '
            } ElseIf (($Scope.disabledPlans.Count -ne 0) -and ($Scope.disabledPlans -notin $DisabledPlans)) {
                Write-Host "    More plans are disabled than expected, the following plans are disabled where they're expected to be enabled: {0}" -f ((($AvailablePlans | Where-Object { $_.ServicePlanId -in ($Scope | Where-Object {$_.disabledPlans -notin $DisabledPlans }).disabledPlans }) | Select-Object @{ Name = "output"; Expression = { "[$($_.servicePlanId)] $($_.ServicePlanName)" }}) | Select-Object -ExpandProperty output) -Join ', '
            } Else {
                Write-Host "    All plans that should be enabled/disabled are as expected..."
            }
        }
    }
}
#endregion

return