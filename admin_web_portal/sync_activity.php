<?php
// admin_web_portal/sync_activity.php
include 'db_config.php';

$type          = $_POST['type'];
$employee_id   = $_POST['employee_id'];
$employee_name = $_POST['employee_name'];
$device        = $_POST['device'];
$timestamp     = $_POST['timestamp'];

$sql = "INSERT INTO activity_logs (type, employee_id, employee_name, device, timestamp)
        VALUES (?, ?, ?, ?, ?)";

$stmt = $conn->prepare($sql);
$stmt->bind_param("sssss", $type, $employee_id, $employee_name, $device, $timestamp);

if ($stmt->execute()) {
    echo "Activity Logged";
} else {
    echo "Error: " . $stmt->error;
}

$stmt->close();
$conn->close();
?>
