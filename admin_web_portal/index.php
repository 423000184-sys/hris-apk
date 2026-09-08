<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>HRIS Admin Master Portal</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-app-compat.js"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-firestore-compat.js"></script>
    <script src="https://www.gstatic.com/firebasejs/10.7.1/firebase-auth-compat.js"></script>
    <script src="https://code.jquery.com/jquery-3.6.0.min.js"></script>
</head>
<body class="bg-slate-900 text-white font-sans">

    <div class="flex h-screen">
        <!-- Sidebar -->
        <div class="w-64 bg-slate-800 border-r border-slate-700 p-6 flex flex-col">
            <h1 class="text-2xl font-bold text-emerald-400 mb-8 flex items-center">🛡️ HRIS MASTER</h1>
            <nav class="space-y-4 flex-1">
                <a href="#" onclick="showSection('attendance')" id="nav-attendance" class="block p-3 rounded-lg bg-emerald-500/10 text-emerald-400 font-bold border border-emerald-500/20">Attendance</a>
                <a href="#" onclick="showSection('employees')" id="nav-employees" class="block p-3 rounded-lg hover:bg-slate-700 text-slate-400">Manage Employees</a>
                <a href="#" onclick="showSection('activity')" id="nav-activity" class="block p-3 rounded-lg hover:bg-slate-700 text-slate-400">Activity Logs</a>
                <a href="#" onclick="showSection('locations')" id="nav-locations" class="block p-3 rounded-lg hover:bg-slate-700 text-slate-400">Live Locations</a>
                <a href="#" onclick="showSection('exports')" id="nav-exports" class="block p-3 rounded-lg hover:bg-slate-700 text-slate-400">Mobile Exports</a>
            </nav>
        </div>

        <div class="flex-1 flex flex-col overflow-hidden">
            <header class="bg-slate-800 border-b border-slate-700 p-4 px-8 flex justify-between items-center">
                <div class="text-sm font-bold uppercase tracking-widest text-slate-500" id="header-title">REAL-TIME ATTENDANCE</div>
                <div class="flex items-center text-emerald-400">
                    <span class="animate-pulse w-2 h-2 rounded-full bg-emerald-400 mr-2"></span> LIVE SYNC
                </div>
            </header>

            <main class="flex-1 overflow-y-auto p-8">
                <!-- Dashboard Stats -->
                <div class="grid grid-cols-1 md:grid-cols-4 gap-6 mb-8">
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-500 text-xs font-bold uppercase mb-1">Total Logs</div>
                        <div class="text-4xl font-black text-emerald-400" id="stat-total">0</div>
                    </div>
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-500 text-xs font-bold uppercase mb-1">Total Employees</div>
                        <div class="text-4xl font-black text-purple-400" id="stat-employees">0</div>
                    </div>
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-500 text-xs font-bold uppercase mb-1">Recent Logins</div>
                        <div class="text-4xl font-black text-blue-400" id="stat-logins">0</div>
                    </div>
                    <div class="bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                        <div class="text-slate-500 text-xs font-bold uppercase mb-1">System Mode</div>
                        <div class="text-xl font-black text-slate-400">ADMIN CONTROL</div>
                    </div>
                </div>

                <!-- Section: Attendance -->
                <div id="section-attendance" class="section-container">
                    <div class="flex justify-between items-center mb-4">
                        <div class="flex items-center space-x-4">
                            <h3 class="text-xl font-bold flex items-center"><span class="mr-2">📅</span> Attendance Master Table</h3>
                            <div class="relative">
                                <span class="absolute inset-y-0 left-0 flex items-center pl-3">
                                    <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
                                </span>
                                <input type="text" id="search-attendance" placeholder="Search employee or ID..." class="bg-slate-800 border border-slate-700 rounded-lg py-2 pl-10 pr-4 text-xs focus:ring-1 focus:ring-emerald-500 outline-none w-64 transition-all">
                            </div>
                        </div>
                        <button onclick="exportCSV('attendance')" class="bg-emerald-600 hover:bg-emerald-500 text-white px-4 py-2 rounded-lg text-xs font-bold transition-all shadow-lg active:scale-95">Export CSV</button>
                    </div>
                    <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-2xl">
                        <table class="w-full text-left" id="table-attendance">
                            <thead class="bg-slate-900/50 text-slate-500 text-[10px] font-black uppercase">
                                <tr>
                                    <th class="p-4 px-6">Employee</th>
                                    <th class="p-4">Time In</th>
                                    <th class="p-4">Time Out</th>
                                    <th class="p-4">Date</th>
                                    <th class="p-4">Status</th>
                                </tr>
                            </thead>
                            <tbody id="attendance-table-body" class="text-sm"></tbody>
                        </table>
                    </div>
                </div>

                <!-- Section: Manage Employees -->
                <div id="section-employees" class="section-container hidden">
                    <div class="grid grid-cols-1 lg:grid-cols-3 gap-8">
                        <!-- Add Employee Form -->
                        <div class="lg:col-span-1 bg-slate-800 p-6 rounded-2xl border border-slate-700 shadow-xl">
                            <h3 class="text-xl font-bold mb-6 flex items-center text-purple-400"><span class="mr-2">👤</span> Add New Employee</h3>
                            <form id="add-employee-form" class="space-y-4">
                                <div>
                                    <label class="block text-[10px] font-black uppercase text-slate-500 mb-1">Full Name</label>
                                    <input type="text" id="emp-name" required class="w-full bg-slate-900 border border-slate-700 rounded-lg p-3 text-sm focus:border-purple-500 outline-none transition-all">
                                </div>
                                <div>
                                    <label class="block text-[10px] font-black uppercase text-slate-500 mb-1">Employee ID</label>
                                    <input type="text" id="emp-id" required class="w-full bg-slate-900 border border-slate-700 rounded-lg p-3 text-sm focus:border-purple-500 outline-none transition-all">
                                </div>
                                <div>
                                    <label class="block text-[10px] font-black uppercase text-slate-500 mb-1">Email Address</label>
                                    <input type="email" id="emp-email" required class="w-full bg-slate-900 border border-slate-700 rounded-lg p-3 text-sm focus:border-purple-500 outline-none transition-all">
                                </div>
                                <div>
                                    <label class="block text-[10px] font-black uppercase text-slate-500 mb-1">Role/Position</label>
                                    <input type="text" id="emp-role" required class="w-full bg-slate-900 border border-slate-700 rounded-lg p-3 text-sm focus:border-purple-500 outline-none transition-all">
                                </div>
                                <div>
                                    <label class="block text-[10px] font-black uppercase text-slate-500 mb-1">Keyfob Serial (NFC Tag ID)</label>
                                    <input type="text" id="emp-nfc" placeholder="e.g. 04:A1:B2:C3:D4:E5:F6" class="w-full bg-slate-900 border border-slate-700 rounded-lg p-3 text-sm focus:border-purple-500 outline-none transition-all font-mono">
                                </div>
                                <div>
                                    <label class="block text-[10px] font-black uppercase text-slate-500 mb-1">Initial PIN (4 Digits)</label>
                                    <input type="password" id="emp-pin" maxlength="4" required class="w-full bg-slate-900 border border-slate-700 rounded-lg p-3 text-sm focus:border-purple-500 outline-none transition-all">
                                </div>
                                <button type="submit" class="w-full bg-purple-600 hover:bg-purple-500 text-white font-bold py-3 rounded-lg shadow-lg active:scale-95 transition-all mt-4">Create Account</button>
                            </form>
                        </div>
                        <!-- Employee List -->
                        <div class="lg:col-span-2">
                            <div class="flex justify-between items-center mb-4">
                                <h3 class="text-xl font-bold flex items-center"><span class="mr-2">📋</span> Employee List</h3>
                                <div class="relative">
                                    <span class="absolute inset-y-0 left-0 flex items-center pl-3">
                                        <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
                                    </span>
                                    <input type="text" id="search-employees" placeholder="Search employees..." class="bg-slate-800 border border-slate-700 rounded-lg py-2 pl-10 pr-4 text-xs focus:ring-1 focus:ring-purple-500 outline-none w-64 transition-all">
                                </div>
                            </div>
                            <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-2xl">
                                <table class="w-full text-left" id="table-employees">
                                    <thead class="bg-slate-900/50 text-slate-500 text-[10px] font-black uppercase">
                                        <tr>
                                            <th class="p-4 px-6">Name & ID</th>
                                            <th class="p-4">Email</th>
                                            <th class="p-4">Keyfob ID</th>
                                            <th class="p-4">Created</th>
                                            <th class="p-4">Action</th>
                                        </tr>
                                    </thead>
                                    <tbody id="employee-table-body" class="text-sm"></tbody>
                                </table>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Section: Activity Logs -->
                <div id="section-activity" class="section-container hidden">
                    <div class="flex justify-between items-center mb-4">
                        <div class="flex items-center space-x-4">
                            <h3 class="text-xl font-bold flex items-center"><span class="mr-2">⚡</span> Activity & Session Logs</h3>
                            <div class="relative">
                                <span class="absolute inset-y-0 left-0 flex items-center pl-3">
                                    <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
                                </span>
                                <input type="text" id="search-activity" placeholder="Search activity..." class="bg-slate-800 border border-slate-700 rounded-lg py-2 pl-10 pr-4 text-xs focus:ring-1 focus:ring-blue-500 outline-none w-64 transition-all">
                            </div>
                        </div>
                        <button onclick="exportCSV('activity')" class="bg-blue-600 hover:bg-blue-500 text-white px-4 py-2 rounded-lg text-xs font-bold transition-all shadow-lg active:scale-95">Export CSV</button>
                    </div>
                    <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-2xl">
                        <table class="w-full text-left" id="table-activity">
                            <thead class="bg-slate-900/50 text-slate-500 text-[10px] font-black uppercase">
                                <tr>
                                    <th class="p-4 px-6">Employee</th>
                                    <th class="p-4">Event Type</th>
                                    <th class="p-4">Timestamp</th>
                                    <th class="p-4">Device</th>
                                </tr>
                            </thead>
                            <tbody id="activity-table-body" class="text-sm"></tbody>
                        </table>
                    </div>
                </div>

                <!-- Section: Live Locations -->
                <div id="section-locations" class="section-container hidden">
                    <div class="flex justify-between items-center mb-4">
                        <h3 class="text-xl font-bold flex items-center"><span class="mr-2">📍</span> Real-time User Tracking</h3>
                        <div class="relative">
                            <span class="absolute inset-y-0 left-0 flex items-center pl-3">
                                <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
                            </span>
                            <input type="text" id="search-locations" placeholder="Search tracked users..." class="bg-slate-800 border border-slate-700 rounded-lg py-2 pl-10 pr-4 text-xs focus:ring-1 focus:ring-rose-500 outline-none w-64 transition-all">
                        </div>
                    </div>
                    <div id="location-cards-grid" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4"></div>
                </div>

                <!-- Section: Mobile Exports -->
                <div id="section-exports" class="section-container hidden">
                    <div class="flex justify-between items-center mb-4">
                        <div class="flex items-center space-x-4">
                            <h3 class="text-xl font-bold flex items-center"><span class="mr-2">📤</span> Mobile Device Exports</h3>
                            <div class="relative">
                                <span class="absolute inset-y-0 left-0 flex items-center pl-3">
                                    <svg class="w-4 h-4 text-slate-500" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"></path></svg>
                                </span>
                                <input type="text" id="search-exports" placeholder="Search export logs..." class="bg-slate-800 border border-slate-700 rounded-lg py-2 pl-10 pr-4 text-xs focus:ring-1 focus:ring-amber-500 outline-none w-64 transition-all">
                            </div>
                        </div>
                        <button onclick="exportCSV('exports')" class="bg-amber-600 hover:bg-amber-500 text-white px-4 py-2 rounded-lg text-xs font-bold transition-all shadow-lg active:scale-95">Export CSV</button>
                    </div>
                    <div class="bg-slate-800 rounded-2xl border border-slate-700 overflow-hidden shadow-2xl">
                        <table class="w-full text-left" id="table-exports">
                            <thead class="bg-slate-900/50 text-slate-500 text-[10px] font-black uppercase">
                                <tr>
                                    <th class="p-4 px-6">Employee</th>
                                    <th class="p-4">Report Type</th>
                                    <th class="p-4">Total Earnings</th>
                                    <th class="p-4">Export Date</th>
                                    <th class="p-4">Status</th>
                                </tr>
                            </thead>
                            <tbody id="export-table-body" class="text-sm"></tbody>
                        </table>
                    </div>
                </div>
            </main>
        </div>
    </div>

    <script>
        const firebaseConfig = {
            apiKey: "AIzaSyAIfs300WjCmdeejsEw50lV2VxMjf-5QVg",
            authDomain: "week-9-activity-53484.firebaseapp.com",
            projectId: "week-9-activity-53484",
            storageBucket: "week-9-activity-53484.firebasestorage.app",
            messagingSenderId: "1095102475957",
            appId: "1:1095102475957:web:45a4624634e83b53e4d8fc",
            measurementId: "G-605G4TDLCX"
        };

        firebase.initializeApp(firebaseConfig);
        const db = firebase.firestore();

        // Reusable filter function
        function applyFilter(inputId, targetSelector, isGrid = false) {
            const val = $(inputId).val().toLowerCase();
            const items = isGrid ? $(targetSelector + " > div") : $(targetSelector + " tr");
            items.filter(function() {
                $(this).toggle($(this).text().toLowerCase().indexOf(val) > -1);
            });
        }

        // Setup Search Listeners
        $("#search-attendance").on("keyup", () => applyFilter("#search-attendance", "#attendance-table-body"));
        $("#search-employees").on("keyup", () => applyFilter("#search-employees", "#employee-table-body"));
        $("#search-activity").on("keyup", () => applyFilter("#search-activity", "#activity-table-body"));
        $("#search-locations").on("keyup", () => applyFilter("#search-locations", "#location-cards-grid", true));
        $("#search-exports").on("keyup", () => applyFilter("#search-exports", "#export-table-body"));

        // 1. Attendance Listener
        db.collection('clock_ins').orderBy('saved_at', 'desc').onSnapshot(snap => {
            const body = $('#attendance-table-body');
            body.empty();
            let count = 0;
            snap.forEach(doc => {
                const d = doc.data();
                count++;
                body.append(`
                    <tr class="border-b border-slate-700/50 hover:bg-slate-700/20">
                        <td class="p-4 px-6 font-bold text-emerald-400">${d.employee_name} <br><span class="text-[10px] text-slate-500 font-mono">${d.employee_id}</span></td>
                        <td class="p-4 font-mono text-emerald-400">${d.time_in}</td>
                        <td class="p-4 font-mono text-blue-400">${d.time_out || '---'}</td>
                        <td class="p-4 text-xs">${d.date}</td>
                        <td class="p-4 uppercase text-[10px] font-black">${d.status}</td>
                    </tr>
                `);
            });
            $('#stat-total').text(count);
            applyFilter("#search-attendance", "#attendance-table-body");
        });

        // 2. Activity Listener
        db.collection('activity_logs').orderBy('timestamp', 'desc').onSnapshot(snap => {
            const body = $('#activity-table-body');
            body.empty();
            let logins = 0;
            snap.forEach(doc => {
                const d = doc.data();
                if(d.type === 'login') logins++;
                body.append(`
                    <tr class="border-b border-slate-700/50 hover:bg-slate-700/20">
                        <td class="p-4 px-6 font-bold text-blue-400">${d.employee_name}</td>
                        <td class="p-4 text-xs font-black">${d.type.toUpperCase()}</td>
                        <td class="p-4 font-mono text-xs">${new Date(d.timestamp?.toDate()).toLocaleString()}</td>
                        <td class="p-4 text-slate-500 text-xs">${d.device}</td>
                    </tr>
                `);
            });
            $('#stat-logins').text(logins);
            applyFilter("#search-activity", "#activity-table-body");
        });

        // 3. Employee List Listener
        db.collection('employees').orderBy('createdAt', 'desc').onSnapshot(snap => {
            const body = $('#employee-table-body');
            body.empty();
            let count = 0;
            snap.forEach(doc => {
                const d = doc.data();
                count++;
                body.append(`
                    <tr class="border-b border-slate-700/50 hover:bg-slate-700/20">
                        <td class="p-4 px-6 font-bold text-purple-400">${d.firstName} ${d.lastName} <br><span class="text-[10px] text-slate-500 font-mono">${d.employeeId}</span></td>
                        <td class="p-4 text-xs">${d.email}</td>
                        <td class="p-4 text-xs font-mono text-emerald-400">${d.nfcTagId || '<span class="text-slate-600">NONE</span>'}</td>
                        <td class="p-4 text-[10px] text-slate-500">${new Date(d.createdAt?.toDate()).toLocaleDateString()}</td>
                        <td class="p-4">
                            <button onclick="deleteEmployee('${doc.id}')" class="text-rose-500 hover:text-rose-400 text-xs font-bold">Delete</button>
                        </td>
                    </tr>
                `);
            });
            $('#stat-employees').text(count);
            applyFilter("#search-employees", "#employee-table-body");
        });

        // 4. Mobile Export Listener
        db.collection('mobile_exports').orderBy('exported_at', 'desc').onSnapshot(snap => {
            const body = $('#export-table-body');
            body.empty();
            snap.forEach(doc => {
                const d = doc.data();
                body.append(`
                    <tr class="border-b border-slate-700/50 hover:bg-slate-700/20">
                        <td class="p-4 px-6 font-bold text-amber-400">${d.employee_name} <br><span class="text-[10px] text-slate-500 font-mono">${d.employee_id}</span></td>
                        <td class="p-4 text-xs font-black uppercase text-slate-300">${d.report_type}</td>
                        <td class="p-4 font-mono text-emerald-400">₱${parseFloat(d.total_earned).toFixed(2)}</td>
                        <td class="p-4 text-xs text-slate-500">${new Date(d.exported_at?.toDate()).toLocaleString()}</td>
                        <td class="p-4">
                            <span class="px-2 py-1 rounded-full bg-emerald-500/10 text-emerald-400 text-[10px] font-black uppercase border border-emerald-500/20">Transferred</span>
                        </td>
                    </tr>
                `);
            });
            applyFilter("#search-exports", "#export-table-body");
        });

        // Add Employee Logic
        $('#add-employee-form').on('submit', async function(e) {
            e.preventDefault();
            const btn = $(this).find('button');
            btn.text('Creating...').prop('disabled', true);

            const name = $('#emp-name').val();
            const id = $('#emp-id').val();
            const email = $('#emp-email').val();
            const role = $('#emp-role').val();
            const pin = $('#emp-pin').val();
            const nfc = $('#emp-nfc').val().trim().toUpperCase();

            try {
                const names = name.split(' ');
                const firstName = names[0];
                const lastName = names.slice(1).join(' ') || ' ';

                const docRef = await db.collection('employees').add({
                    employeeId: id.toUpperCase(),
                    firstName: firstName,
                    lastName: lastName,
                    email: email.toLowerCase(),
                    position: role,
                    nfcTagId: nfc || null,
                    tempPin: pin,
                    createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                    updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
                    department: 'Corporate',
                    status: 'active'
                });

                $.post('sync_employee.php', {
                    id: docRef.id,
                    employee_id: id.toUpperCase(),
                    first_name: firstName,
                    last_name: lastName,
                    email: email.toLowerCase(),
                    position: role,
                    nfc_tag_id: nfc || '',
                    temp_pin: pin
                }).done(function(res) {
                    alert('Employee Account Created and Keyfob Registered Successfully!');
                    $('#add-employee-form')[0].reset();
                });

            } catch (error) {
                console.error(error);
                alert('Error: ' + error.message);
            } finally {
                btn.text('Create Account').prop('disabled', false);
            }
        });

        function deleteEmployee(docId) {
            if(confirm('Are you sure you want to delete this employee?')) {
                db.collection('employees').doc(docId).delete();
            }
        }

        // Location Listener
        db.collection('user_locations').onSnapshot(snap => {
            const grid = $('#location-cards-grid');
            grid.empty();
            snap.forEach(doc => {
                const d = doc.data();
                grid.append(`
                    <div class="bg-slate-800 p-4 rounded-xl border-l-4 ${d.is_inside_perimeter ? 'border-emerald-500' : 'border-rose-500'} shadow-lg">
                        <div class="flex justify-between items-start mb-2">
                            <span class="font-black text-sm">${d.employee_id}</span>
                            <span class="text-[9px] font-black px-2 py-0.5 rounded-full ${d.is_inside_perimeter ? 'bg-emerald-500/20 text-emerald-400' : 'bg-rose-500/20 text-rose-400'}">${d.is_inside_perimeter ? 'INSIDE' : 'OUTSIDE'}</span>
                        </div>
                        <div class="text-[10px] text-slate-500 font-mono mb-2">${d.latitude.toFixed(4)}, ${d.longitude.toFixed(4)}</div>
                        <div class="text-[10px] text-slate-400">Sync: ${new Date(d.last_updated?.toDate()).toLocaleTimeString()}</div>
                    </div>
                `);
            });
            applyFilter("#search-locations", "#location-cards-grid", true);
        });

        function showSection(id) {
            $('.section-container').addClass('hidden');
            $(`#section-${id}`).removeClass('hidden');
            $('#header-title').text(`REAL-TIME ${id.toUpperCase().replace('-', ' ')}`);
            $('nav a').removeClass('bg-emerald-500/10 text-emerald-400 border border-emerald-500/20').addClass('text-slate-400 hover:bg-slate-700');
            $(`#nav-${id}`).addClass('bg-emerald-500/10 text-emerald-400 border border-emerald-500/20').removeClass('text-slate-400');
        }

        function exportCSV(type) {
            const tableId = `table-${type}`;
            const rows = document.querySelectorAll(`#${tableId} tr`);
            let csvContent = "";
            rows.forEach(row => {
                const cols = row.querySelectorAll("th, td");
                const rowData = Array.from(cols).map(col => {
                    let text = col.innerText.replace(/(\r\n|\n|\r)/gm, " ").replace(/\s+/g, ' ').trim();
                    return `"${text}"`;
                }).join(",");
                csvContent += rowData + "\r\n";
            });
            const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
            const url = URL.createObjectURL(blob);
            const link = document.createElement("a");
            link.setAttribute("href", url);
            link.setAttribute("download", `HRIS_${type.toUpperCase()}_${new Date().toISOString().slice(0,10)}.csv`);
            link.style.visibility = 'hidden';
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
        }
    </script>
</body>
</html>
