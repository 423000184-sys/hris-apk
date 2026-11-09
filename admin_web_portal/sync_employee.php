<?php
// admin_web_portal/sync_employee.php
include 'db_config.php';

$id          = $_POST['id']; // Firebase Doc ID
$employee_id = $_POST['employee_id'];
$first_name  = $_POST['first_name'];
$last_name   = $_POST['last_name'];
$email       = $_POST['email'];
$position    = $_POST['position'];
$nfc_tag_id  = $_POST['nfc_tag_id'];
$temp_pin    = $_POST['temp_pin'];

// Using the structure from hris_biometrics.sql
$sql = "INSERT INTO employees (id, employee_id, first_name, last_name, email, position, nfc_tag_id, pin_hash, department)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'Corporate')
        ON DUPLICATE KEY UPDATE
        first_name = VALUES(first_name),
        last_name = VALUES(last_name),
        email = VALUES(email),
        position = VALUES(position),
        nfc_tag_id = VALUES(nfc_tag_id),
        pin_hash = VALUES(pin_hash)";

$stmt = $conn->prepare($sql);
// Note: In a production app, you should hash the PIN here or handle it securely.
// For now, we store it in pin_hash to match the app's expected schema.
$stmt->bind_param("ssssssss", $id, $employee_id, $first_name, $last_name, $email, $position, $nfc_tag_id, $temp_pin);

if ($stmt->execute()) {
    echo "Employee & Keyfob Synced to MySQL";
} else {
    echo "Error: " . $stmt->error;
}

$stmt->close();
$conn->close();
?>
