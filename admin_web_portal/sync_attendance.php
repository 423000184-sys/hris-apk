<?php
// admin_web_portal/sync_attendance.php
include 'db_config.php';

$attendance_id = $_POST['attendance_id'];
$employee_id   = $_POST['employee_id'];
$employee_name = $_POST['employee_name'];
$time_in       = isset($_POST['time_in']) && $_POST['time_in'] != '' ? $_POST['time_in'] : null;
$time_out      = isset($_POST['time_out']) && $_POST['time_out'] != '' && $_POST['time_out'] != '--:--' ? $_POST['time_out'] : null;
$date          = $_POST['date'];
$status        = isset($_POST['status']) ? $_POST['status'] : 'present';

// Using ON DUPLICATE KEY UPDATE to handle both Clock In and Clock Out
// If it's a Clock Out, it will update the existing record's time_out and status.
$sql = "INSERT INTO attendance_logs (attendance_id, employee_id, employee_name, time_in, time_out, date, status)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE
        time_out = IFNULL(VALUES(time_out), time_out),
        status = IFNULL(VALUES(status), status)";

$stmt = $conn->prepare($sql);
$stmt->bind_param("sssssss", $attendance_id, $employee_id, $employee_name, $time_in, $time_out, $date, $status);

if ($stmt->execute()) {
    echo "Attendance Synced Successfully";
} else {
    echo "Error: " . $stmt->error;
}

$stmt->close();
$conn->close();
?>
