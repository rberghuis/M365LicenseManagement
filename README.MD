# Microsoft 365 Multi-Geo
A repo containing information on Microsoft 365 License Management.

## Introduction
This script provides the capability to validate Group Based Licensing, to catch whenever Microsoft auto-adds/enables a new (Service) Plan within a (License) Sku.

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

## How to use?
Read the code itself so you're aware of what it will do to your data. Create back-ups, run through your change processes etc.

## License
See [LICENSE](LICENSE), the code found in this repository is provided as-is under the MIT license

## Links
A list of usefull links
- [List acquired subscriptions](https://learn.microsoft.com/en-us/graph/api/subscribedsku-list)
- [Get Entra ID groups](https://learn.microsoft.com/en-us/graph/api/group-get)
- [Advanced query capabilities on Microsoft Entra ID objects](https://learn.microsoft.com/en-us/graph/aad-advanced-queries)