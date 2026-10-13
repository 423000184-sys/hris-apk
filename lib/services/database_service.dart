// lib/services/database_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import '../models/employee.dart';
import '../models/attendance.dart';
import 'package:uuid/uuid.dart';

class DatabaseService {
  static DatabaseService? _instance;  
  static Database? _db;

  final _attendanceUpdateController = StreamController<String?>.broadcast();
  Stream<String?> get onAttendanceChanged => _attendanceUpdateController.stream;

  DatabaseService._();
  static DatabaseService get instance => _instance ??= DatabaseService._();

  static const String _rootFolder = 'HRIS_Biometrics';

  Future<Database?> get database async {
    if (kIsWeb) return null;
    _db ??= await _initDb();
    return _db;
  }

  Future<Database?> _initDb() async {
    if (kIsWeb) return null;
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'hris_biometrics.db');
      return openDatabase(
        path,
        version: 4,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      );
    } catch (e) {
      debugPrint('DB Init Error: $e');
      return null;
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      final tableInfo = await db.rawQuery('PRAGMA table_info(employees)');
      final hasPinSalt = tableInfo.any((col) => col['name'] == 'pin_salt');
      if (!hasPinSalt) {
        await db.execute('ALTER TABLE employees ADD COLUMN pin_salt TEXT');
      }
    }
    if (oldVersion < 4) {
      final tableInfo = await db.rawQuery('PRAGMA table_info(employees)');
      final hasNfcTagId = tableInfo.any((col) => col['name'] == 'nfc_tag_id');
      if (!hasNfcTagId) {
        await db.execute('ALTER TABLE employees ADD COLUMN nfc_tag_id TEXT');
      }
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        payload TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        retry_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        last_attempt TEXT,
        error_message TEXT
      )
    ''');
  }

  Future<void> _onCreate(Database db, int version) async {
    final now = DateTime.now().toIso8601String();

    await db.execute('''CREATE TABLE employees (
        id TEXT PRIMARY KEY, employee_id TEXT UNIQUE NOT NULL,
        first_name TEXT NOT NULL, last_name TEXT NOT NULL,
        email TEXT NOT NULL, department TEXT NOT NULL, position TEXT NOT NULL,
        phone TEXT, photo_path TEXT, face_embedding TEXT,
        fingerprint_hash TEXT, pin_hash TEXT, pin_salt TEXT, nfc_tag_id TEXT,
        is_active INTEGER DEFAULT 1,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL
      )''');

    await db.execute('''CREATE TABLE attendance (
        id TEXT PRIMARY KEY, employee_id TEXT NOT NULL,
        date TEXT NOT NULL, time_in TEXT, time_out TEXT,
        status TEXT DEFAULT 'present', method TEXT NOT NULL,
        latitude REAL, longitude REAL, device_id TEXT, notes TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (employee_id) REFERENCES employees(id)
      )''');

    await db.execute('''CREATE TABLE leave_requests (
        id TEXT PRIMARY KEY,
        employee_id TEXT NOT NULL,
        leave_type TEXT NOT NULL,
        start_date TEXT NOT NULL,
        end_date TEXT NOT NULL,
        reason TEXT,
        status TEXT DEFAULT 'pending',
        approved_by TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (employee_id) REFERENCES employees(id)
      )''');

    await db.execute('''CREATE TABLE audit_logs (
        id TEXT PRIMARY KEY, user_id TEXT, action TEXT NOT NULL,
        details TEXT, device_id TEXT, timestamp TEXT NOT NULL,
        is_suspicious INTEGER DEFAULT 0
      )''');

    await db.execute('''CREATE TABLE departments (
        id TEXT PRIMARY KEY, name TEXT UNIQUE NOT NULL, created_at TEXT NOT NULL
      )''');

    await db.execute('''CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY, type TEXT NOT NULL, payload TEXT NOT NULL,
        status TEXT DEFAULT 'pending', retry_count INTEGER DEFAULT 0,
        created_at TEXT NOT NULL, last_attempt TEXT, error_message TEXT
      )''');

    await _seedData(db, now);
  }

  Future<void> _seedData(Database db, String now) async {
    for (final dept in ['Engineering', 'HR', 'Finance', 'Operations', 'Sales', 'Marketing']) {
      await db.insert('departments',
          {'id': dept.toLowerCase(), 'name': dept, 'created_at': now},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  Future<SyncFromFilesResult> syncLocalFilesToDatabase() async {
    if (kIsWeb) return SyncFromFilesResult(inserted: 0, skipped: 0, errors: []);
    final db = await database;
    if (db == null) return SyncFromFilesResult(inserted: 0, skipped: 0, errors: []);
    int inserted = 0, skipped = 0;
    final errors = <String>[];

    try {
      final dates = await getLocalAttendanceDates();
      for (final date in dates) {
        final records = await getLocalRecordsForDate(date);
        for (final record in records) {
          final event = record['event'] as String?;
          if (event != 'clock_in' && event != 'clock_out') continue;
          final attendanceId = record['attendance_id'] as String?;
          if (attendanceId == null) continue;

          try {
            if (event == 'clock_in') {
              final existing = await db.query('attendance', where: 'id = ?', whereArgs: [attendanceId]);
              if (existing.isNotEmpty) {
                skipped++;
                continue;
              }

              final empRows = await db.query('employees',
                  where: 'employee_id = ?', whereArgs: [record['employee_id']]);
              if (empRows.isEmpty) continue;

              await db.insert('attendance', {
                'id': attendanceId,
                'employee_id': empRows.first['id'],
                'date': record['date'],
                'time_in': record['time_in'],
                'time_out': null,
                'status': record['status'] ?? 'present',
                'method': record['auth_method'] ?? 'pin',
                'created_at': record['saved_at'] ?? DateTime.now().toIso8601String(),
              });
              inserted++;
            } else {
              final timeOut = record['time_out'] as String?;
              if (timeOut == null) continue;
              await db.update('attendance', {'time_out': timeOut},
                  where: 'id = ? AND time_out IS NULL', whereArgs: [attendanceId]);
              skipped++;
            }
          } catch (e) {
            errors.add(e.toString());
          }
        }
      }
      if (inserted > 0) _attendanceUpdateController.add(null);
    } catch (e) {
      errors.add(e.toString());
    }
    return SyncFromFilesResult(inserted: inserted, skipped: skipped, errors: errors);
  }

  Future<Directory> get localStorageRoot async {
    Directory? base;
    if (Platform.isAndroid) {
      base = Directory('/storage/emulated/0/Download');
      if (!await base.exists()) {
        final extDirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (extDirs != null && extDirs.isNotEmpty) base = extDirs.first;
      }
    }
    base ??= await getApplicationDocumentsDirectory();
    final root = Directory('${base.path}/$_rootFolder');
    if (!await root.exists()) await root.create(recursive: true);
    return root;
  }

  Future<Directory> _folder(String sub, String date) async {
    final root = await localStorageRoot;
    final dir = Directory('${root.path}/$sub/$date');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File?> saveClockInFile(
      {required Employee employee, required Attendance attendance}) async {
    if (kIsWeb) return null;
    final date = attendance.date;
    final time =
    (attendance.timeIn ?? DateFormat('HH:mm:ss').format(DateTime.now()))
        .replaceAll(':', '-');
    final attDir = await _folder('attendance', date);
    final file = File('${attDir.path}/${employee.employeeId}_clock_in_$time.json');
    await file.writeAsString(_encode({
      'event': 'clock_in',
      'employee_id': employee.employeeId,
      'employee_name': '${employee.firstName} ${employee.lastName}',
      'date': date,
      'time_in': attendance.timeIn,
      'status': attendance.status.name,
      'auth_method': attendance.method.name,
      'attendance_id': attendance.id,
      'saved_at': DateTime.now().toIso8601String(),
    }));
    return file;
  }

  Future<File?> saveClockOutFile(
      {required Employee employee,
        required Attendance attendance,
        required String timeOut}) async {
    if (kIsWeb) return null;
    final date = attendance.date;
    final timeTag = timeOut.replaceAll(':', '-');
    final attDir = await _folder('attendance', date);
    final file = File('${attDir.path}/${employee.employeeId}_clock_out_$timeTag.json');
    await file.writeAsString(_encode({
      'event': 'clock_out',
      'employee_id': employee.employeeId,
      'date': date,
      'time_out': timeOut,
      'attendance_id': attendance.id,
      'saved_at': DateTime.now().toIso8601String(),
    }));
    return file;
  }

  Future<File?> savePayrollExportFile(Employee employee, Map<String, dynamic> payroll) async {
    if (kIsWeb) return null;
    final root = await localStorageRoot;
    final payrollDir = Directory('${root.path}/payroll');
    if (!await payrollDir.exists()) await payrollDir.create(recursive: true);
    
    final csvFilename = 'PAYROLL_${employee.employeeId}_${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
    final csvFile = File('${payrollDir.path}/$csvFilename');
    final csvBuffer = StringBuffer();
    csvBuffer.writeln('PAYROLL REPORT (CSV)');
    csvBuffer.writeln('Employee: ${employee.fullName}, ID: ${employee.employeeId}');
    csvBuffer.writeln('Total Hours: ${payroll['totalHours'].toStringAsFixed(2)}, Gross: ₱${payroll['grossPay'].toStringAsFixed(2)}');
    csvBuffer.writeln('');
    csvBuffer.writeln('DATE,TIME IN,TIME OUT,HOURS,EARNINGS (₱)');
    for (var r in (payroll['records'] as List)) {
      final hrs = double.tryParse(r['hours'] ?? '0') ?? 0.0;
      csvBuffer.writeln('${r['date']},${r['time_in']},${r['time_out']},${r['hours']},${(hrs * 150).toStringAsFixed(2)}');
    }
    await csvFile.writeAsString(csvBuffer.toString());

    final excel = Excel.createExcel();
    final sheet = excel['Payroll'];
    sheet.appendRow([
      TextCellValue('DATE'),
      TextCellValue('TIME IN'),
      TextCellValue('TIME OUT'),
      TextCellValue('HOURS'),
      TextCellValue('EARNINGS (₱)')
    ]);
    for (var r in (payroll['records'] as List)) {
      final hrs = double.tryParse(r['hours'] ?? '0') ?? 0.0;
      sheet.appendRow([
        TextCellValue(r['date'] ?? ''),
        TextCellValue(r['time_in'] ?? ''),
        TextCellValue(r['time_out'] ?? ''),
        TextCellValue(r['hours'] ?? ''),
        TextCellValue((hrs * 150).toStringAsFixed(2))
      ]);
    }
    final excelFilename = csvFilename.replaceAll('.csv', '.xlsx');
    final excelFile = File('${payrollDir.path}/$excelFilename');
    await excelFile.writeAsBytes(excel.save()!);

    final pdf = pw.Document();
    pdf.addPage(pw.Page(build: (pw.Context context) {
      return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('PAYROLL REPORT (PDF)', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.Text('Employee: ${employee.fullName} (${employee.employeeId})'),
        pw.Text('Total Earnings: PHP ${payroll['grossPay'].toStringAsFixed(2)}'),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(context: context, data: [
          ['DATE', 'IN', 'OUT', 'HRS', 'PHP'],
          ...((payroll['records'] as List).map((r) => [r['date'], r['time_in'], r['time_out'], r['hours'], (double.parse(r['hours'] ?? '0') * 150).toStringAsFixed(2)]))
        ]),
      ]);
    }));
    final pdfFilename = csvFilename.replaceAll('.csv', '.pdf');
    final pdfFile = File('${payrollDir.path}/$pdfFilename');
    await pdfFile.writeAsBytes(await pdf.save());

    return csvFile;
  }

  String _encode(Map<String, dynamic> data) =>
      const JsonEncoder.withIndent('  ').convert(data);

  Future<String> getLocalStoragePath() async {
    if (kIsWeb) return 'Web Storage';
    return (await localStorageRoot).path;
  }

  Future<String> getLocalStorageSize() async {
    if (kIsWeb) return '0 B';
    final root = await localStorageRoot;
    int bytes = 0;
    try {
      if (await root.exists()) {
        await for (final e in root.list(recursive: true)) {
          if (e is File) bytes += await e.length();
        }
      }
    } catch (_) {}
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1048576) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1048576).toStringAsFixed(1)} MB';
  }

  Future<List<String>> getLocalAttendanceDates() async {
    if (kIsWeb) return [];
    final root = await localStorageRoot;
    final dir = Directory('${root.path}/attendance');
    if (!await dir.exists()) return [];
    return dir
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split('/').last)
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  Future<List<Map<String, dynamic>>> getLocalRecordsForDate(String date) async {
    if (kIsWeb) return [];
    final root = await localStorageRoot;
    final dir = Directory('${root.path}/attendance/$date');
    if (!await dir.exists()) return [];
    final results = <Map<String, dynamic>>[];
    for (final f in dir.listSync().whereType<File>()) {
      if (f.path.endsWith('.json')) {
        try {
          final data = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
          data['_file'] = f.path.split('/').last;
          results.add(data);
        } catch (_) {}
      }
    }
    return results;
  }

  Future<void> clearDemoData(String demoId) async {
    final db = await database;
    if (db == null) return;
    await db.delete('attendance', where: 'employee_id = ?', whereArgs: [demoId]);
  }

  Future<String?> insertEmployee(Employee employee) async {
    final db = await database;
    if (db == null) return null;
    await db.insert('employees', employee.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    return employee.id;
  }

  Future<void> updateEmployee(Employee employee) async {
    final db = await database;
    if (db == null) return;
    await db.update(
      'employees',
      employee.toMap(),
      where: 'id = ?',
      whereArgs: [employee.id],
    );
  }

  Future<List<Employee>> getAllEmployees() async {
    final db = await database;
    if (db == null) return [];
    final maps = await db.query('employees',
        where: 'is_active = ?', whereArgs: [1], orderBy: 'first_name ASC');
    return maps.map((m) => Employee.fromMap(m)).toList();
  }

  Future<Employee?> getEmployeeById(String id) async {
    final db = await database;
    if (db == null) return null;
    final maps = await db.query('employees', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? Employee.fromMap(maps.first) : null;
  }

  Future<Employee?> getEmployeeByEmployeeId(String employeeId) async {
    final db = await database;
    if (db == null) return null;
    final maps = await db.query('employees',
        where: 'UPPER(employee_id) = ?',
        whereArgs: [employeeId.toUpperCase()]);
    return maps.isNotEmpty ? Employee.fromMap(maps.first) : null;
  }

  Future<Employee?> getEmployeeByEmail(String email) async {
    final db = await database;
    if (db == null) return null;
    final maps = await db.query('employees',
        where: 'email = ?',
        whereArgs: [email.toLowerCase()]);
    return maps.isNotEmpty ? Employee.fromMap(maps.first) : null;
  }

  Future<Employee?> getEmployeeByNfcTag(String nfcTagId) async {
    final db = await database;
    if (db == null) return null;
    final cleanId = nfcTagId.replaceAll(':', '').toUpperCase();

    final maps = await db.query('employees',
        where: 'UPPER(nfc_tag_id) = ? OR UPPER(REPLACE(nfc_tag_id, ":", "")) = ?',
        whereArgs: [nfcTagId.toUpperCase(), cleanId]);

    return maps.isNotEmpty ? Employee.fromMap(maps.first) : null;
  }

  Future<void> logAttendance(Attendance attendance) async {
    final db = await database;
    if (db == null) return;
    await db.insert('attendance', attendance.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    _attendanceUpdateController.add(attendance.employeeId);
  }

  Future<void> updateTimeOut(String attendanceId, String timeOut) async {
    final db = await database;
    if (db == null) return;
    final maps = await db.query('attendance', where: 'id = ?', whereArgs: [attendanceId]);
    final String? empId = maps.isNotEmpty ? maps.first['employee_id'] as String? : null;

    await db.update('attendance', {'time_out': timeOut},
        where: 'id = ?', whereArgs: [attendanceId]);
    _attendanceUpdateController.add(empId);
  }

  Future<Attendance?> getTodayAttendance(String employeeId) async {
    final db = await database;
    if (db == null) return null;
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final maps = await db.query('attendance',
        where: 'employee_id = ? AND date = ?',
        whereArgs: [employeeId, today],
        orderBy: 'created_at DESC',
        limit: 1);
    return maps.isNotEmpty ? Attendance.fromMap(maps.first) : null;
  }

  Future<List<Attendance>> getAttendanceByEmployee(String employeeId, {int limit = 10}) async {
    final db = await database;
    if (db == null) return [];
    final maps = await db.query('attendance',
        where: 'employee_id = ?',
        whereArgs: [employeeId],
        orderBy: 'date DESC, created_at DESC',
        limit: limit);
    return maps.map((m) => Attendance.fromMap(m)).toList();
  }

  Future<Map<String, int>> getAttendanceStats(String employeeId) async {
    final db = await database;
    if (db == null) return {'present': 0, 'late': 0, 'absent': 0};
    final month = DateFormat('yyyy-MM').format(DateTime.now());
    
    Future<int> getCount(String status) async {
      final result = await db.rawQuery(
          "SELECT COUNT(*) FROM attendance WHERE employee_id=? AND date LIKE ? AND status=?",
          [employeeId, '$month%', status]
      );
      return Sqflite.firstIntValue(result) ?? 0;
    }

    return {
      'present': await getCount('present'),
      'late': await getCount('late'),
      'absent': await getCount('absent'),
    };
  }

  Future<List<Map<String, dynamic>>> getWeeklyWorkHours(String employeeId) async {
    final db = await database;
    if (db == null) return [];
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final results = <Map<String, dynamic>>[];
    for (int i = 0; i < 7; i++) {
      final dateStr = DateFormat('yyyy-MM-dd').format(startOfWeek.add(Duration(days: i)));
      final maps = await db.query('attendance',
          where: 'employee_id = ? AND date = ?',
          whereArgs: [employeeId, dateStr]);
      double hours = 0;
      for (var m in maps) {
        try {
          final att = Attendance.fromMap(m);
          if (att.timeIn != null && att.timeOut != null) {
            final s = DateTime.parse('${att.date} ${att.timeIn}');
            final e = DateTime.parse('${att.date} ${att.timeOut}');
            hours += e.difference(s).inMinutes / 60.0;
          }
        } catch (_) {}
      }
      results.add({'day': i, 'hours': hours});
    }
    return results;
  }

  Future<Map<String, dynamic>> getPayrollSummary(String employeeId, {int days = 15}) async {
    final db = await database;
    if (db == null) {
      return {
        'totalHours': 0.0,
        'daysPresent': 0,
        'grossPay': 0.0,
        'cutoff': 'N/A',
        'rate': 150.0,
        'records': [],
      };
    }
    final now = DateTime.now();
    final cutoffStr = DateFormat('yyyy-MM-dd').format(now.subtract(Duration(days: days)));
    final maps = await db.query('attendance',
        where: 'employee_id = ? AND date >= ?',
        whereArgs: [employeeId, cutoffStr],
        orderBy: 'date ASC');

    double totalHours = 0;
    int daysPresent = 0;
    final records = <Map<String, dynamic>>[];

    for (var m in maps) {
      final att = Attendance.fromMap(m);
      if (att.timeIn != null && att.timeOut != null) {
        try {
          final s = DateTime.parse('${att.date} ${att.timeIn}');
          final e = DateTime.parse('${att.date} ${att.timeOut}');
          final diff = e.difference(s);
          final h = diff.inMinutes / 60.0;
          totalHours += h;
          daysPresent++;
          records.add({
            'date': att.date,
            'time_in': att.timeIn,
            'time_out': att.timeOut,
            'hours': h.toStringAsFixed(2),
            'status': att.status.name,
          });
        } catch (_) {}
      }
    }
    return {
      'totalHours': totalHours,
      'daysPresent': daysPresent,
      'grossPay': totalHours * 150.0,
      'cutoff': 'Cutoff: ${DateFormat('MMM dd').format(now.subtract(Duration(days: days)))} - ${DateFormat('MMM dd').format(now)}',
      'rate': 150.0,
      'records': records,
    };
  }

  Future<void> insertAuditLog(Map<String, dynamic> log) async {
    final db = await database;
    if (db == null) return;
    await db.insert('audit_logs', log, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> insertLeaveRequest(Map<String, dynamic> leave) async {
    final db = await database;
    if (db == null) return;
    await db.insert('leave_requests', {
      'id': const Uuid().v4(),
      ...leave,
      'status': 'pending',
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteEmployeeData(String employeeId) async {
    final db = await database;
    if (db == null) return;
    await db.transaction((txn) async {
      await txn.delete('attendance', where: 'employee_id = ?', whereArgs: [employeeId]);
      await txn.delete('leave_requests', where: 'employee_id = ?', whereArgs: [employeeId]);
      await txn.delete('audit_logs', where: 'user_id = ?', whereArgs: [employeeId]);
      await txn.delete('employees', where: 'id = ?', whereArgs: [employeeId]);
    });
    _attendanceUpdateController.add(null);
  }

  void dispose() {
    _attendanceUpdateController.close();
  }
}

class SyncFromFilesResult {
  final int inserted, skipped;
  final List<String> errors;
  SyncFromFilesResult({required this.inserted, required this.skipped, required this.errors});
  bool get hasChanges => inserted > 0;
}
