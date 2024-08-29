##############################################################################
# This script is intended to sync threat alerts from SentinelOne to HaloPSA 
# You can schedule it via an Azure Function or use something like Powershell Universal
# The script will follow the following routine:
# 1) Map new threats from SentinelOne to new or existing tickets
#    - Get all threats from SentinelOne that don't have an external ticket ID set yet
#    - If there is already an open ticket for that hash, the threat will get mapped to the existing ticket. This only works when the script can find a matching halo asset for the SentinelOne threat.
#    - If there is no open ticket for that hash or no matching halo asset could be found, the threat will get mapped to a new ticket
#    - Mapping the threat to a ticket means:
#      - External ticket ID in SentinelOne is set
#      - Corrosponding Halo asset is linked to the ticket (only when creating a new ticket)
#      - Ticket CF for file hash is set (only when creating a new ticket)
#      - Threat ID get's added to CF for threat IDs
#      - Threat ID get's added to CF for unresolved threat IDs
# 2) Update existing tickets with changed status of threats in SentinelOne
#    - Get all tickets with the specified ticket type ID from HaloPSA
#    - Loop through all retrieved tickets and check if there are any unresolved threat IDs by checking the CF in the ticket
#    - If there is a ticket that has unresolved threat IDs and the corrosponding threat in SentinelOne is not resolved, put a note in the ticket
#    - This step has some issues documented in comments above the code
# 3) Re-open tickets that have been closed without resolving the corrosponding threat in SentinelOne
#    - Get all threats from SentinelOne that are not resolved and have an external ticket ID set
#    - Re-open the tickets
#
# There are a couple of requirements for this script/integration to work:
# - You need a tickettype for SentinelOne alerts
# - The SentinelOne alert tckettype needs to have custom fields for filehash, threat IDs and unresolved threat IDs
# - Your HaloPSA assets should have a custom field named Hostname which contains, you guessed it, the hostname of the device
# - You need an API key for SentinelOne and the URL for your console
# - You need an API key for HaloPSA, obviously
# - Please make sure all your API keys and URLs are working and have the correct permissions as this script misses some foolproofing as of now
#
# Disclaimer:
# - I am not a professional developer by any means, I just try things out until they work
# - This script probably has A LOT of room for improvement, but for now it works
# - Only because this script works good for our workflows, it doesn't mean it works good for yours
# - This script hasn't been tested for very long and therefor you should use it at your own risk, but that should be obvious
# - Best of luck, your humble @2_click
#
# Thanks to:
# @homotechsual (https://homotechsual.dev/) - For an awesome HaloAPI powershell module
# @apievangelist (http://apievangelist.com) - For an awesome SentinelOne Postman API collection 
#
##############################################################################
# SETTINGS
##############################################################################
#ID of ticket type in halo. Make sure that the ticket type has the mentioned custom fields
$HALO_TICKET_TYPE_ID = 56
#ID of halo site that shall be used if no matching asset in halo can be found
$HALO_FALLBACK_SITE_ID = 265
# ID of the Halo custom field for the sha1 filehash
$HALO_CF_THREAT_FILEHASH = 182
# ID of the Halo custom field for the threat IDs
$HALO_CF_THREAT_IDS = 183
# ID of the Halo custom field for the unresolved threat IDs
$HALO_CF_UNRESOLVED_THREAT_IDS = 184
# Action (outcome) ID for the re-open action in Halo
$HALO_ACTION_ID_REOPEN = 13
# Action (outcome) NAME for the integration update action in Halo, that should be similar to a private note action. The fields in halo for this action should only include >Note<
$HALO_ACTION_NAME_INTEGRATION_UPDATE = 'Integration update'
# Status of ticket after re-open action
$HALO_STATUS_AFTER_REOPEN = 2

# Date format that should be used for information in notes
$DATE_FORMAT_STRING = "dd.MM.yyyy HH:mm"

# Set the Halo connection details
$VaultName = "keyfault-pwsh"
$HaloClientID = Get-AzKeyVaultSecret -VaultName $VaultName -Name "haloclientid" -AsPlainText
$HaloClientSecret = Get-AzKeyVaultSecret -VaultName $VaultName -Name "haloclientsecret" -AsPlainText
$HaloURL = Get-AzKeyVaultSecret -VaultName $VaultName -Name "halourl" -AsPlainText

# SentinelOne connection data
# Looks like this: https://yourinstance.sentinelone.net/
$S1_BASE_URL = Get-AzKeyVaultSecret -VaultName $VaultName -Name "s1baseurl" -AsPlainText
# API token/key is usually 80 characters long
$S1_API_TOKEN = Get-AzKeyVaultSecret -VaultName $VaultName -Name "s1apitoken" -AsPlainText

##############################################################################
# FUNCTIONS
##############################################################################
function Invoke-S1WebRequest ($resource_uri, $method, $body) {
    $S1_Headers = @{}
    $S1_Headers.Add('Authorization', "ApiToken $S1_API_TOKEN")
    if ($method -eq "Get") {
        $request = Invoke-WebRequest -Method Get -Uri ($S1_BASE_URL + $resource_uri) -Headers $S1_Headers -ErrorAction Stop
    }
    if ($method -eq "Post") {
        $S1_Headers.Add("Content-Type", "application/json")
        $request = Invoke-WebRequest -Method Post -Uri ($S1_BASE_URL + $resource_uri) -Headers $S1_Headers -Body $($body | ConvertTo-Json)  -ErrorAction Stop
    }

    try {
        $obj = $($request.content | ConvertFrom-Json).data
    }
    catch {
        Write-Error "SentinelOne API did not return any good data"
        $obj = $null
    }
    return $obj 
}

function Set-S1ThreatExternalTicketId ($threat_id, $external_id) {
    $s1_body = @{
        filter = @{
            ids = "$threat_id"
        }
        data   = @{
            externalTicketId = "$external_id"
        }
    }
    $s1_body = New-Object PSObject -Property $s1_body
    
    $null = Invoke-S1WebRequest -method "Post" -body $s1_body -resource_uri "/web/api/v2.1/threats/external-ticket-id" 
}

##############################################################################
# BEGIN SCRIPT
##############################################################################

# Connect to Halo
try {
    Connect-HaloAPI -URL $HaloURL -ClientId $HaloClientID -ClientSecret $HaloClientSecret -Scopes "all" -ErrorAction Stop
}
catch {
    Write-Error "Error connecting to the HaloPSA API"
    exit 1
}

# Check if SentinelOne API is ready
$s1_system_info = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/system/info"
if ($null -eq $s1_system_info) {
    Write-Error "Error connecting to the SentinelOne API"
    exit 1
}

# STEP 1
# Create/assign tickets for threats that don't have a ticket yet
Write-Host "Retrieving threats from SentinelOne to create/update tickets"
$threats = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/threats?incidentStatuses=unresolved&externalTicketExists=false"
Write-host "Found $($threats.count) threats"
foreach ($threat in $threats) {
    #Fetching additional Endpoint details for the threat
    $s1_endpoint = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/agents?uuids=$($threat.agentDetectionInfo.agentUuid)" 
    $halo_assets = $null
    $halo_asset = $null
    $halo_assets = Get-HaloAsset -Search $s1_endpoint.computerName -FullObjects -includeinactive # Remove -includeinactive if you only want to search for active assets

    if ($halo_assets.count -gt 1) {
        # Received multiple assets from halo
        # We cannot use Where-Object in a clean one-liner because of the way Halo handles (custom)fields
        foreach ($asset in $halo_assets) {
            $halo_hostname = $($asset.fields | Where-Object -FilterScript { $_.name -eq "Hostname" }).Value
            if ($halo_hostname -eq $s1_endpoint.computerName) {
                # Current asset's name matches the name of the S1 endpoint
                if ($s1_endpoint.siteName -eq $asset.client_name) {
                    # Client of asset is the same as the client in SentinelOne, assign halo_asset
                    $halo_asset = $asset
                    break # We found the asset so we can break the loop
                }
            }
        }
        
        
    }
    if ($halo_assets.count -eq 1) {
        # Received exactly one asset from halo
        # Assign halo_asset
        $halo_asset = $halo_assets
    }

    if ($null -eq $halo_asset) {
        Write-Warning "No Halo Asset found"
    }

    # Timestamps in SentinelOne are UTC so convert them to local time
    $threat.threatInfo.createdAt = $threat.threatInfo.createdAt.ToLocalTime()
    $date_time_string_german = $threat.threatInfo.createdAt.ToString($DATE_FORMAT_STRING)

    $report_string = "<b>New S1 threat from $($date_time_string_german)</b>" + [System.Environment]::NewLine
    $report_string += "<b style=`"color: red;`">>>>DO NOT MERGE THIS TICKET<<</b>" + [System.Environment]::NewLine
    $report_string += "<a href=""$S1_BASE_URL/incidents/threats/$($threat.threatinfo.threatId)/overview"">Show in SentinelOne console</a>" + [System.Environment]::NewLine 
    $report_string += [System.Environment]::NewLine 
    $report_string += "-- FILE INFORMATION" + [System.Environment]::NewLine 
    $report_string += "Filename: $($threat.threatInfo.threatName) " + [System.Environment]::NewLine    
    $report_string += "File hash: $($threat.threatInfo.sha1)" + [System.Environment]::NewLine     
    $report_string += [System.Environment]::NewLine 
    $report_string += "-- CLIENT INFORMATION" + [System.Environment]::NewLine 
    $report_string += "Site name: $($threat.agentDetectionInfo.siteName)" + [System.Environment]::NewLine 
    $report_string += "Site ID: $($threat.agentDetectionInfo.siteId)" + [System.Environment]::NewLine 
    $report_string += [System.Environment]::NewLine 
    $report_string += "-- ENDPOINT INFORMATION" + [System.Environment]::NewLine 
    $report_string += "Last login: $($threat.agentDetectionInfo.agentLastLoggedInUserName)" + [System.Environment]::NewLine 
    $report_string += "Last login (UPN): $($threat.agentDetectionInfo.agentLastLoggedInUpn)" + [System.Environment]::NewLine 
    $report_string += [System.Environment]::NewLine 
    $report_string += "External IP: $($threat.agentDetectionInfo.externalIp)" + [System.Environment]::NewLine 
    $report_string += "Internal IP: $($threat.agentDetectionInfo.agentIpV4)" + [System.Environment]::NewLine 
    $report_string += "Agent OS: $($threat.agentDetectionInfo.agentOsName)" + [System.Environment]::NewLine 
    $report_string += "Agent UUID: $($threat.agentDetectionInfo.agentUuid)" + [System.Environment]::NewLine 
    $report_string += "Agent Hostname: $($s1_endpoint.computerName)" + [System.Environment]::NewLine 
    $report_string += "Agent Domain: $($s1_endpoint.domain)" + [System.Environment]::NewLine 
    $report_string += [System.Environment]::NewLine 
    $report_string += "-- HALO INFORMATION" + [System.Environment]::NewLine 
    $report_string += "Asset Inventory Number: $($halo_asset.inventory_number)" + [System.Environment]::NewLine 
    $report_string += [System.Environment]::NewLine
    $report_string += [System.Environment]::NewLine
    $report_string += "<b style=`"color: red;`">>>>DO NOT MERGE THIS TICKET<<</b>" + [System.Environment]::NewLine

    $updated_existing_ticket = $false
    # Check if we have a matching Halo asset. Only then we can update existing tickets and link existing threat IDs to the ticket
    if ($null -ne $halo_asset) {
        # Matching Halo asset has been found
        $existing_tickets = Get-HaloTicket -RequestTypeID $HALO_TICKET_TYPE_ID -FullObjects -OpenOnly -AssetID $halo_asset.id
        foreach ($existing_ticket in $existing_tickets) {
            # Load hash from ticket
            $file_hash = $($existing_ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneThreatFileHash" }).Value
            if ($file_hash -eq $threat.threatInfo.sha1) {
                # Existing ticket has been found
                Write-Host "Adding threat to existing ticket as note" -ForegroundColor Yellow
                # Prepare action
                $halo_action = @{
                    ticket_id      = $existing_ticket.id
                    outcome        = $HALO_ACTION_NAME_INTEGRATION_UPDATE
                    datetime       = [DateTime]::Now
                    note           = $report_string
                    hiddenfromuser = $true
                }
                # Post action to ticket
                $note = New-HaloAction -Action $halo_action

                # Get existing threat IDs from ticket and add the current threat id to it
                $threat_ids_string = $null
                $threat_ids = $null
                $threat_ids_string = $($existing_ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneThreatIds" }).Value
                $threat_ids = $threat_ids_string.split(",")
                $threat_ids += $threat.threatInfo.threatId
                $threat_ids_string = $threat_ids -join ","

                # Get existing unresolved threat IDs from ticket and add the current threat id to it
                $unresolved_threat_ids_string = $null
                $unresolved_threat_ids = $null
                $unresolved_threat_ids_string = $($existing_ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneUnresolvedThreatIds" }).Value
                $unresolved_threat_ids = $unresolved_threat_ids_string.split(",")
                $unresolved_threat_ids += $threat.threatInfo.threatId
                $unresolved_threat_ids_string = $unresolved_threat_ids -join ","

                #Write all threat IDs to the custom field, comma seperated
                $halo_ticket = @{
                    id           = $existing_ticket.id
                    customfields = @(
                        @{
                            id    = $HALO_CF_THREAT_IDS
                            value = "$threat_ids_string"
                        },
                        @{
                            id    = $HALO_CF_UNRESOLVED_THREAT_IDS
                            value = "$unresolved_threat_ids_string"
                        }
                    )
                }
                $null = Set-HaloTicket -Ticket $halo_ticket
                $updated_existing_ticket = $true
                #Update S1 Threat external ticket ID
                Set-S1ThreatExternalTicketId -threat_id $threat.threatinfo.threatId -external_id $existing_ticket.id
                break # Break loop as we have found a matching ticket
            }
        }
    }


    if ($updated_existing_ticket -eq $false) {
        # No existing ticket has been updated so a new ticket will be created
        Write-Host "Creating new ticket for threat" -ForegroundColor Green

        if ($null -ne $halo_asset) {
            # There is a matching Halo Asset
            $halo_ticket = @{
                summary       = "SentinelOne threat: $($threat.threatInfo.threatName) - $($s1_endpoint.computerName)"
                details       = $report_string.Replace([System.Environment]::NewLine, "<br>")
                site_id       = $halo_asset.site_id
                tickettype_id = $HALO_TICKET_TYPE_ID
                datetime      = [DateTime]::Now
                assets        = @(
                    @{
                        id = $halo_asset.id
                    }
                )
                customfields  = @(
                    @{
                        id    = $HALO_CF_THREAT_FILEHASH
                        value = "$($threat.threatInfo.sha1)"
                    },
                    @{
                        id    = $HALO_CF_THREAT_IDS
                        value = "$($threat.threatInfo.threatid)"
                    },
                    @{
                        id    = $HALO_CF_UNRESOLVED_THREAT_IDS
                        value = "$($threat.threatInfo.threatid)"
                    }
                )
            }
        }
        else {
            # There is no matching Halo Asset
            $halo_ticket = @{
                summary       = "SentinelOne threat: $($threat.threatInfo.threatName) - $($s1_endpoint.computerName)"
                details       = $report_string.Replace([System.Environment]::NewLine, "<br>")
                site_id       = $HALO_FALLBACK_SITE_ID
                tickettype_id = $HALO_TICKET_TYPE_ID
                datetime      = [DateTime]::Now
                customfields  = @(
                    @{
                        id    = $HALO_CF_THREAT_FILEHASH
                        value = "$($threat.threatInfo.sha1)"
                    },
                    @{
                        id    = $HALO_CF_THREAT_IDS
                        value = "$($threat.threatInfo.threatid)"
                    },
                    @{
                        id    = $HALO_CF_UNRESOLVED_THREAT_IDS
                        value = "$($threat.threatInfo.threatid)"
                    }
                )
            }
        }

        $new_ticket = New-HaloTicket -Ticket $halo_ticket
        if ($null -ne $new_ticket) {
            Write-Host "Successfully created Ticket with ID: $($new_ticket.id)" -ForegroundColor Green
            Set-S1ThreatExternalTicketId -threat_id $threat.threatinfo.threatId -external_id $new_ticket.id
        }

    }
}

# STEP 2
# Help users to identify if a ticket is still relevant by putting notes in it for each threat has has already been marked as solved in SentinelOne. 
# Loop through all open and closed tickets with specefic ticket type, read CF which contains one or more Threat IDs and see if they have been resolved in SentinelOne. If so, put note in Ticket.
# This method could become a problem once there are a lot of tickets with the specified ticket type as we get both open tickets and closed tickets.
# We do this because we want to put updates in tickets that are closed as well in order to remove the threat id from the unresolved threat IDs fields
# We could add -openonly to the Get-HaloTicket command to reduce time spend, but then the custom field won't get updated for closed tickets.
# Current workarounds: Only get tickets of the last 2 months



Write-Host "Retrieving tickets from HaloPSA to put notes in tickets when it is required"
$existing_tickets = $null
$existing_tickets = Get-HaloTicket -RequestTypeID $HALO_TICKET_TYPE_ID -FullObjects -StartDate $((Get-Date).AddMonths(-2))
Write-Host "Found $($existing_tickets.Count) tickets"

foreach ($existing_ticket in $existing_tickets) {
    $threat_hash = $($existing_ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneThreatFileHash" }).Value
    $threat_ids_string = $null
    $unresolved_threat_ids_string = $null
    $threat_ids_string = $($existing_ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneThreatIds" }).Value
    if ($null -eq $threat_ids_string -or $threat_ids_string.Length -lt 1) {
        # No threat IDs found in custom field
        continue
    }
    $threat_ids = $threat_ids_string.split(",")

    $unresolved_threat_ids_string = $($existing_ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneUnresolvedThreatIds" }).Value
    if ($null -eq $unresolved_threat_ids_string -or $unresolved_threat_ids_string.Length -lt 1) {
        # No unresolved threat IDs found in custom field
        continue
    }
    $unresolved_threat_ids = $unresolved_threat_ids_string.split(",")
    foreach ($threat_id in $unresolved_threat_ids) {
        # Get SentinelOne threat that has the correct ID and is already resolved
        $threat = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/threats?incidentStatuses=resolved&ids=$threat_id"
        $s1_endpoint = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/agents?uuids=$($threat.agentDetectionInfo.agentUuid)" 

        # Build the URL to view all linked threats
        $ticket_id = $existing_ticket.id
        $all_linked_threats_url = "$S1_BASE_URL/incidents/threats?filter={%22externalTicketId__contains%22:%22\%22$ticket_id\%22%22,%22timeTitle%22:%22Last%20Year%22}"
        if ($null -ne $threat) {
            # Found a threat that is resolved for a ticket that is still open
            Write-Host "SentinelOne threat $threat_id has been resolved, therefor posting update to ticket $($existing_ticket.id)"
            # Get storyline to find out who marked the threat has resolved
            $storyline = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/threats/$threat_id/timeline"
            $relevant_story_entries = $storyline | Where-Object -FilterScript { $_.primaryDescription -like "*changed the analyst verdict*" -or $_.primaryDescription -like "*changed the incident status*" }
            $relevant_story_entries = $relevant_story_entries | Sort-Object -Property createdAt

            # Post note ticket
            $note_text = "<b>A linked SentinelOne threat has been marked as resolved</b><br>" 
            $note_text += "<a href=""$S1_BASE_URL/incidents/threats/$($threat.threatinfo.threatId)/overview"">Show resolved threat in SentinelOne console</a><br>"
            $note_text += "<a href=""$all_linked_threats_url"">Show all linked threats in SentinelOne console</a><br>"
            $note_text += "Hint: Check the field <i>SentinelOne Unresolved Threat IDs</i> to see if any theats are remaining<br>"
            $note_text += "-- INFO:<br>" 
            foreach ($relevant_story_entry in $relevant_story_entries) {
                # SentinelOne timestamps are UTC
                $relevant_story_entry.createdAt = $relevant_story_entry.createdAt.ToLocalTime()
                $date_time_string_german = $relevant_story_entry.createdAt.ToString($DATE_FORMAT_STRING)
                $note_text += "$($date_time_string_german): $($relevant_story_entry.primaryDescription)<br>"

            }
            # Prepare action
            $halo_action = @{
                ticket_id      = $existing_ticket.id
                outcome        = $HALO_ACTION_NAME_INTEGRATION_UPDATE
                datetime       = [DateTime]::Now
                note           = $note_text
                hiddenfromuser = $true
            }
            # Post action to ticket
            $note = New-HaloAction -Action $halo_action

            # Remove threat ID from Ticket CF SentinelOneUnresolvedThreadIds
            $unresolved_threat_ids = $unresolved_threat_ids | Where-Object -FilterScript { $_ -ne "$threat_id" }
            $unresolved_threat_ids_string = $unresolved_threat_ids -join "," 
            #Write all threat IDs to the custom field, comma seperated
            $halo_ticket = @{
                id           = $existing_ticket.id
                customfields = @(
                    @{
                        id    = $HALO_CF_UNRESOLVED_THREAT_IDS
                        value = "$unresolved_threat_ids_string"
                    }
                )
            }
            $null = Set-HaloTicket -Ticket $halo_ticket

            
        }
    }
}
# STEP 3
# Prevent users from closing tickets that are not unresolved in SentinelOne
# Loop through all SentinelOne Cases that are not resolved and have an external ticket ID. Check Ticket status for each of the threats and if a ticket is closed, reopen it. 
Write-Host "Retrieving threats from SentinelOne to re-open tickets that have been closed without resolving the threat."
$threats = $null
$threats = Invoke-S1WebRequest -method "Get" -resource_uri "/web/api/v2.1/threats?incidentStatuses=unresolved,in_progress&externalTicketExists=true"
Write-Host "Found $($threats.Count) threats that are not resolved and have an external ticket ID set"

foreach ($threat in $threats) {
    $ticket_id = $threat.threatInfo.externalTicketId
    $ticket = Get-HaloTicket -TicketID $ticket_id 
    # Not too s ure if this is the best way to check if the ticket is closed. I would like to avoid using specefic status IDs because those are tricky
    if ($null -ne $ticket.closure_time) {
        # Closed ticket has been found in Halo
        Write-Host "Ticket $ticket_id is closed, but a threat refering that ticket is not resolved yet, reopening the ticket..."
        $note_text = "<b>A linked SentinelOne threat hasn't been resolved yet, therefor re-opening the ticket.</b><br>"
        $note_text += "<a href=""$S1_BASE_URL/incidents/threats/$($threat.threatinfo.threatId)/overview"">Show in SentinelOne console</a>" + [System.Environment]::NewLine 
        # Prepare action
        $halo_action = @{
            ticket_id      = $ticket_id
            outcome_id     = $HALO_ACTION_ID_REOPEN
            datetime       = [DateTime]::Now
            note           = $note_text
            sendemail      = $false
            new_status     = $HALO_STATUS_AFTER_REOPEN
            hiddenfromuser = $false
        }
        # Post action to ticket
        $note = New-HaloAction -Action $halo_action

        $unresolved_threat_ids_string = $($ticket.customfields | Where-Object -FilterScript { $_.Name -eq "CFSentinelOneUnresolvedThreatIds" }).Value
        if ($null -eq $unresolved_threat_ids_string -or $unresolved_threat_ids_string.Length -lt 1) {
            # No unresolved threat IDs found in custom field
        }
        else {
            $unresolved_threat_ids = $unresolved_threat_ids_string.split(",")
        }

        # Todo: Check if threat ID already exists in this field

        # Add threat ID to Ticket CF SentinelOneUnresolvedThreadIds
        $unresolved_threat_ids += $threat.threatInfo.threatId
        $unresolved_threat_ids_string = $unresolved_threat_ids -join "," 
        #Write all threat IDs to the custom field, comma seperated
        $halo_ticket = @{
            id           = $ticket.id
            customfields = @(
                @{
                    id    = $HALO_CF_UNRESOLVED_THREAT_IDS
                    value = "$unresolved_threat_ids_string"
                }
            )
        }
        $null = Set-HaloTicket -Ticket $halo_ticket

    }
}