# This script uses the TeamViewer15_Logfile.log file, which is updated in real-time.
# It detects sessions that are currently in progress and connections that have already ended.
# It will also detect both desktop sessions and file transfer sessions.
# It will also detect login attempts (failed connections)
# Examples
# 2024/06/28 20:23:37.280  3160  3604 S0   CPersistentParticipantManager::AddParticipant: [1651063400,876631011] type=6 name=Joe Doe | Pro IT Services
# 2024/06/28 22:49:14.140  3160  3608 S0   CPersistentParticipantManager::RemoveParticipant: [1651063400,2002352381]
# 2024/06/28 22:01:34.365  3160  3616 S0   AuthenticationBlocker::Allocate: allocate ok for DyngateID 1349779002, attempt number 1
# Delimited by one or more spaces
# Timestamps are local imezone

# If the following text is found in the peer name, the connection will be considered friendly
$friendly_identifier = "YOUR COMPANY"
$connections = @()
$failed_connections = @()

if (-not (Test-Path -Path "C:\Program Files (x86)\TeamViewer\TeamViewer15_Logfile.log")) {
    Write-Host "TeamViewer log could not be found"
    return
}

foreach($line in Get-Content "C:\Program Files (x86)\TeamViewer\TeamViewer15_Logfile.log" -Encoding UTF8 -ErrorAction SilentlyContinue) {


    # Get the timestamp from the line, if it contains one
    if ($line -match '^\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}\.\d{3}') {
        # Extract the timestamp part of the line
        $timestamp = $matches[0]
        # Convert the timestamp string to a DateTime object
        $time_started = [datetime]::ParseExact($timestamp, 'yyyy/MM/dd HH:mm:ss.fff', $null)
        $time_ago =  New-TimeSpan –Start $time_started –End $(Get-Date)
    }


    # Check if the log line contains information on a new participant
    if ($line -match "CPersistentParticipantManager::AddParticipant:") {
        # A new participant joined
        # Split the log line into parts based on the first occurrence of "CPersistentParticipantManager::AddParticipant:"
        $main_parts = $line -split "CPersistentParticipantManager::AddParticipant:", 2
        
        # Extract the participant info
        $participant_info = $main_parts[1].Trim()
        
        # Use regex to extract participant IDs, type, and name
        $participant_ids_match = [regex]::Match($participant_info, "\[(.+?)\]")
        $type_match = [regex]::Match($participant_info, "type=(\d+)")
        $name_match = [regex]::Match($participant_info, "name=(.+)")
        
        if ($participant_ids_match.Success -and $type_match.Success -and $name_match.Success) {
            $participant_ids = $participant_ids_match.Groups[1].Value.Split(',')
            $participant_id_1 = $participant_ids[0] # That is the connecting TeamViewer ID
            $participant_id_2 = $participant_ids[1] # It's unknown what this ID is
            $type = $type_match.Groups[1].Value
            $name = $name_match.Groups[1].Value
            
            if ($type -ne 3) {
                # type=3 is the local device (the host) joining the session. We only care for remote parties joining the session which is usually type=6
                $connection = [PSCustomObject]@{
                    time_started     = $time_started
                    time_ago = $time_ago
                    peer_id  = $participant_id_1
                    peer_name            = $name
                }
                $connections += $connection
            }
        }
    }
    
    if ($line -match "AuthenticationBlocker::Allocate:") {
        if ($line -match 'attempt number (\d+)') {
            $attempt_count = $matches[1]
        }
        if ($line -match 'DyngateID (\d+)') {
            $dyngate_id = $matches[1]
        }
        $failed_connection = [PSCustomObject]@{
            time_started     = $time_started
            time_ago = $time_ago
            peer_id = $dyngate_id
            attempt_count = $attempt_count
        }
        $failed_connections += $failed_connection
    }
}

# Filter out friendly connections
$foreign_connections = $connections | Where-Object -FilterScript {$_.peer_name -notlike "*$friendly_identifier*"}
# Filter out old connections
$foreign_connections = $foreign_connections | Where-Object -FilterScript {$_.time_ago.totalhours -lt 24}

# Filter out old failed connections
$failed_connections = $failed_connections | Where-Object -FilterScript {$_.time_ago.totalhours -lt 24}


$healthy = $true
$issues = ""
$detail_messages = @()

if ($null -ne $foreign_connections) {
    $healthy = $false
    $issues += "foreign_connections_found $([Environment]::NewLine)"
    foreach ($foreign_connection in $foreign_connections) {
        $text = "TeamViewer ID $($foreign_connection.peer_id) ($($foreign_connection.peer_name)) started a session"
        $detail_message = [PSCustomObject]@{
            time_started     = $foreign_connection.time_started
            text = $text
        }
        $detail_messages += $detail_message
    }
}

if ($null -ne $failed_connections) {
    $healthy = $false
    $issues += "failed_connections_found $([Environment]::NewLine)"
    foreach ($failed_connection in $failed_connections) {
        $text = "TeamViewer ID $($failed_connection.peer_id) attempted a connection (attempt #$($failed_connection.attempt_count))"
        $detail_message = [PSCustomObject]@{
            time_started     = $failed_connection.time_started
            text = $text
        }
        $detail_messages += $detail_message
    }
}

if ($healthy -eq $true) {
    Write-Host "Healthy"
} else {
    Write-Host "Unhealthy"
    Write-Host $issues
    $detail_messages = $detail_messages | Sort-Object { [datetime]$_.time_started }
    foreach ($detail_message in $detail_messages) {
        Write-Host "$($detail_message.time_started.ToString("dd.MM.yyyy HH:mm:ss")): $($detail_message.text)"
    }
}
