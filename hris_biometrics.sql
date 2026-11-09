CREATE DATABASE IF NOT EXISTS hris_biometrics;
USE hris_biometrics;

-- 1. Employees Table (Registered Users)
CREATE TABLE IF NOT EXISTS employees (
    id VARCHAR(100) PRIMARY KEY, -- Firebase UID
    employee_id VARCHAR(50) UNIQUE NOT NULL,
    first_name VARCHAR(100) NOT NULL,
    last_name VARCHAR(100) NOT NULL,
    email VARCHAR(100) NOT NULL,
    department VARCHAR(100),
    position VARCHAR(100),
    pin_hash TEXT,
    pin_salt TEXT,
    nfc_tag_id VARCHAR(100),
    role VARCHAR(20) DEFAULT 'user',
    is_active TINYINT(1) DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- 2. Attendance Logs (Unified Clock In/Out)
CREATE TABLE IF NOT EXISTS attendance_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    attendance_id VARCHAR(100) UNIQUE, -- Unique ID from Mobile/Firebase
    employee_id VARCHAR(50) NOT NULL,
    employee_name VARCHAR(200),
    time_in VARCHAR(50),
    time_out VARCHAR(50),
    date DATE,
    status VARCHAR(20), -- late, present, etc.
    saved_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 3. Activity Logs (Login, Logout, Registration)
CREATE TABLE IF NOT EXISTS activity_logs (
    id INT AUTO_INCREMENT PRIMARY KEY,
    type ENUM('registration', 'login', 'logout') NOT NULL,
    employee_id VARCHAR(50),
    employee_name VARCHAR(200),
    device VARCHAR(50) DEFAULT 'Mobile App',
    details TEXT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 4. User Locations (Live Tracking every 1 minute)
CREATE TABLE IF NOT EXISTS user_locations (
    id INT AUTO_INCREMENT PRIMARY KEY,
    firebase_uid VARCHAR(100) UNIQUE,
    employee_id VARCHAR(50),
    latitude DOUBLE,
    longitude DOUBLE,
    accuracy DOUBLE,
    distance_from_office DOUBLE, -- in meters
    is_inside_perimeter TINYINT(1), -- 1 for true, 0 for false
    last_updated DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);

-- Optional: Indices for faster searching
CREATE INDEX idx_emp_id ON attendance_logs(employee_id);
CREATE INDEX idx_date ON attendance_logs(date);
CREATE INDEX idx_activity_type ON activity_logs(type);
