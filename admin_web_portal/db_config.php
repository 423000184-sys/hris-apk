<?php
// admin_web_portal/db_config.php
$host = "localhost";
$user = "root";
$pass = "";
$db   = "hris_biometrics";

$conn = new mysqli($host, $user, $pass, $db);

if ($conn->connect_error) {
    die("Connection failed: " . $conn->connect_error);
}

// Create tables if they don't exist
$conn->query("CREATE TABLE IF NOT EXISTS attendance_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    employee_id VARCHAR(50),
    employee_name VARCHAR(100),
    time_in VARCHAR(50),
    time_out VARCHAR(50),
    date DATE,
    status VARCHAR(20),
    firebase_id VARCHAR(100) UNIQUE
)");
?>
