// lib/models/employee.dart

class _Unset {
  const _Unset();
}

const _unset = _Unset();

class Employee {
  final String id;
  final String employeeId;
  final String firstName;
  final String lastName;
  final String email;
  final String department;
  final String position;
  final String? phone;
  final String? photoPath;
  final String? photoUrl;
  final String? faceEmbedding;
  final String? fingerprintHash;
  final String? pinHash;
  final String? pinSalt;
  final String? nfcTagId;
  final bool isActive;
  final bool wfhAccess;
  final DateTime createdAt;
  final DateTime updatedAt;

  Employee({
    required this.id,
    required this.employeeId,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.department,
    required this.position,
    this.phone,
    this.photoPath,
    this.photoUrl,
    this.faceEmbedding,
    this.fingerprintHash,
    this.pinHash,
    this.pinSalt,
    this.nfcTagId,
    this.isActive = true,
    this.wfhAccess = false,
    required this.createdAt,
    required this.updatedAt,
  });

  String get fullName => '$firstName $lastName'.trim();

  String get initials =>
      '${firstName.isNotEmpty ? firstName[0] : ''}${lastName.isNotEmpty ? lastName[0] : ''}'
          .toUpperCase();

  bool get isDriver => position.toLowerCase() == 'driver';
  bool get hasFaceEnrolled => faceEmbedding != null;
  bool get hasFingerprintEnrolled => fingerprintHash != null;
  bool get hasPinSet => pinHash != null;
  bool get hasNfcEnrolled => nfcTagId != null;

  String? get displayPhoto {
    if (photoUrl != null && photoUrl!.isNotEmpty && photoUrl != '—') {
      return photoUrl;
    }
    if (photoPath != null && photoPath!.isNotEmpty && photoPath != '—') {
      return photoPath;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'employee_id': employeeId,
    'first_name': firstName,
    'last_name': lastName,
    'email': email,
    'department': department,
    'position': position,
    'phone': phone,
    'photo_path': photoPath,
    'photo_url': photoUrl,
    'face_embedding': faceEmbedding,
    'fingerprint_hash': fingerprintHash,
    'pin_hash': pinHash,
    'pin_salt': pinSalt,
    'nfc_tag_id': nfcTagId,
    'is_active': isActive ? 1 : 0,
    'wfh_access': wfhAccess ? 1 : 0,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  Map<String, dynamic> toFirestore() => {
    'employeeId': employeeId,
    'firstName': firstName,
    'lastName': lastName,
    'fullName': fullName,
    'email': email,
    'department': department,
    'position': position,
    'role': position,
    'phone': phone,
    'photoPath': photoPath,
    'photoUrl': photoUrl,
    'faceEmbedding': faceEmbedding,
    'fingerprintHash': fingerprintHash,
    'pinHash': pinHash,
    'pinSalt': pinSalt,
    'nfcTagId': nfcTagId,
    'status': isActive ? 'active' : 'inactive',
    'wfhAccess': wfhAccess,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory Employee.fromMap(Map<String, dynamic> map) => Employee(
    id: map['id']?.toString() ?? '',
    employeeId: map['employee_id']?.toString() ?? '',
    firstName: map['first_name']?.toString() ?? '',
    lastName: map['last_name']?.toString() ?? '',
    email: map['email']?.toString() ?? '',
    department: map['department']?.toString() ?? '',
    position: map['position']?.toString() ?? '',
    phone: map['phone']?.toString(),
    photoPath: map['photo_path']?.toString(),
    photoUrl: map['photo_url']?.toString(),
    faceEmbedding: map['face_embedding']?.toString(),
    fingerprintHash: map['fingerprint_hash']?.toString(),
    pinHash: map['pin_hash']?.toString(),
    pinSalt: map['pin_salt']?.toString(),
    nfcTagId: map['nfc_tag_id']?.toString(),
    isActive: _toBool(map['is_active']),
    wfhAccess: _toBool(map['wfh_access'] ?? map['wfhAccess']),
    createdAt: _toDateTime(map['created_at']),
    updatedAt: _toDateTime(map['updated_at']),
  );

  factory Employee.fromFirestore(Map<String, dynamic> map, String docId) {
    String firstName = map['firstName']?.toString() ?? '';
    String lastName = map['lastName']?.toString() ?? '';

    if (firstName.isEmpty) {
      final combined = (map['fullName'] ?? map['name'] ?? '').toString().trim();
      final parts = combined.split(' ').where((e) => e.isNotEmpty).toList();
      firstName = parts.isNotEmpty ? parts.first : '';
      lastName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    }

    final status = map['status']?.toString() ?? 'active';
    final isActive = status == 'active';

    return Employee(
      id: docId,
      employeeId: map['employeeId']?.toString() ?? docId,
      firstName: firstName,
      lastName: lastName,
      email: map['email']?.toString() ?? '',
      department: (map['department'] ?? map['role'] ?? '').toString(),
      position: (map['position'] ?? map['role'] ?? '').toString(),
      phone: map['phone']?.toString(),
      photoPath: map['photoPath']?.toString(),
      photoUrl: map['photoUrl']?.toString(),
      faceEmbedding: map['faceEmbedding']?.toString(),
      fingerprintHash: map['fingerprintHash']?.toString(),
      pinHash: (map['pinHash'] ?? map['pin'])?.toString(),
      pinSalt: map['pinSalt']?.toString(),
      nfcTagId: map['nfcTagId']?.toString(),
      isActive: isActive,
      wfhAccess: _toBool(map['wfhAccess'] ?? map['wfh_access']),
      createdAt: _toDateTime(map['createdAt']),
      updatedAt: _toDateTime(map['updatedAt']),
    );
  }

  Employee copyWith({
    Object? phone = _unset,
    Object? photoPath = _unset,
    Object? photoUrl = _unset,
    Object? faceEmbedding = _unset,
    Object? fingerprintHash = _unset,
    Object? pinHash = _unset,
    Object? pinSalt = _unset,
    Object? nfcTagId = _unset,
    String? department,
    String? position,
    bool? isActive,
    bool? wfhAccess,
  }) =>
      Employee(
        id: id,
        employeeId: employeeId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        department: department ?? this.department,
        position: position ?? this.position,
        phone: phone is _Unset ? this.phone : phone as String?,
        photoPath: photoPath is _Unset ? this.photoPath : photoPath as String?,
        photoUrl: photoUrl is _Unset ? this.photoUrl : photoUrl as String?,
        faceEmbedding:
        faceEmbedding is _Unset ? this.faceEmbedding : faceEmbedding as String?,
        fingerprintHash: fingerprintHash is _Unset
            ? this.fingerprintHash
            : fingerprintHash as String?,
        pinHash: pinHash is _Unset ? this.pinHash : pinHash as String?,
        pinSalt: pinSalt is _Unset ? this.pinSalt : pinSalt as String?,
        nfcTagId: nfcTagId is _Unset ? this.nfcTagId : nfcTagId as String?,
        isActive: isActive ?? this.isActive,
        wfhAccess: wfhAccess ?? this.wfhAccess,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  static bool _toBool(dynamic v) {
    if (v is bool) return v;
    if (v is int) return v == 1;
    if (v is String) return v == '1' || v.toLowerCase() == 'true';
    return false;
  }

  static DateTime _toDateTime(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is DateTime) return v;
    try {
      return DateTime.parse(v.toString());
    } catch (_) {
      return DateTime.now();
    }
  }
}