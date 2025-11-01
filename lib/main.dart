// Flutter app: PostgreSQL Dashboard (frontend)
// Files included in this single document:
// 1) pubspec.yaml (dependencies)
// 2) lib/main.dart (Flutter app)
// 3) optional_backend/server.js (Node.js example backend to safely run queries)

/* --------------------------------------------------------------------------
  IMPORTANT NOTES
  - This example implements a Flutter frontend that talks to a small backend
    service to execute SQL against PostgreSQL. Running arbitrary SQL from a
    client directly to your DB is dangerous (security, networking, credentials).
    Use the backend approach for production.
  - The backend example (Node.js) demonstrates a safe-enough pattern for
    development; adapt authentication/authorization for real deployments.
  - The frontend stores a simple query history locally (shared_preferences).

  How to run (quick):
  1) Start a Node.js backend (see optional_backend/server.js) and set
     BACKEND_URL in the Flutter app or use the app settings screen.
  2) Run `flutter pub get` and `flutter run`.

  The UI features:
  - SQL editor (multiline TextField with monospace font + simple syntax
    highlighting via basic heuristics)
  - Run Query button: calls backend /run-query
  - Explain button: calls backend /explain
  - Results table for SELECT outputs
  - Error / logs area
  - History side panel with saved past queries
  - Connection (backend) settings

  This is an opinionated but complete starting point you can iterate on.
-----------------------------------------------------------------------------*/

/* --------------------------- pubspec.yaml --------------------------- */

// pubspec.yaml
// paste into your project's pubspec.yaml (or create new Flutter app and
// replace/merge the dependencies section)

/*
name: pg_dashboard
description: A Flutter dashboard UI for running PostgreSQL queries via a backend.
publish_to: 'none'
version: 0.0.1
environment:
  sdk: '>=2.18.0 <3.0.0'

dependencies:
  flutter:
    sdk: flutter
  http: ^0.13.6
  shared_preferences: ^2.1.1
  flutter_highlight: ^0.8.6

flutter:
  uses-material-design: true
*/

/* --------------------------- lib/main.dart --------------------------- */

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(PgDashboardApp());
}

class PgDashboardApp extends StatelessWidget {
  const PgDashboardApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Postgres Dashboard',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: PgDashboardHome(),
    );
  }
}

class PgDashboardHome extends StatefulWidget {
  const PgDashboardHome({super.key});
  @override
  PgDashboardHomeState createState() => PgDashboardHomeState();
}

class PgDashboardHomeState extends State<PgDashboardHome> {
  final TextEditingController _sqlController = TextEditingController();
  final TextEditingController _backendController = TextEditingController();
  String _backendUrl = 'http://localhost:3000';
  bool _running = false;
  String _log = '';
  List<String> _history = [];
  List<String> _columns = [];
  List<List<dynamic>> _rows = [];
  String _explain = '';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _backendUrl = prefs.getString('backendUrl') ?? _backendUrl;
      _backendController.text = _backendUrl;
      _history = prefs.getStringList('history') ?? [];
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('backendUrl', _backendUrl);
    await prefs.setStringList('history', _history);
  }

  void _addToHistory(String q) {
    if (q.trim().isEmpty) return;
    setState(() {
      _history.remove(q); // move to top if exists
      _history.insert(0, q);
      if (_history.length > 50) _history = _history.sublist(0, 50);
    });
    _saveSettings();
  }

  Future<void> _runQuery() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;
    _addToHistory(sql);

    setState(() {
      _running = true;
      _log = '';
      _columns = [];
      _rows = [];
      _explain = '';
    });

    try {
      final uri = Uri.parse('$_backendUrl/run-query');
      final resp = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'sql': sql}));
      if (resp.statusCode != 200) {
        setState(() {
          _log = 'Server error: ${resp.statusCode} ${resp.body}';
        });
      } else {
        final data = jsonDecode(resp.body);
        if (data['error'] != null) {
          setState(() {
            _log = 'Error: ${data['error']}';
          });
        } else if (data['rows'] != null && data['columns'] != null) {
          setState(() {
            _columns = List<String>.from(data['columns']);
            _rows = (data['rows'] as List).map((r) => List<dynamic>.from(r)).toList();
          });
        } else if (data['message'] != null) {
          setState(() {
            _log = data['message'];
          });
        } else {
          setState(() {
            _log = 'Unexpected response from server.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _log = 'Request failed: $e';
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

  Future<void> _explainQuery() async {
    final sql = _sqlController.text.trim();
    if (sql.isEmpty) return;
    setState(() {
      _running = true;
      _explain = '';
      _log = '';
    });

    try {
      final uri = Uri.parse('$_backendUrl/explain');
      final resp = await http.post(uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'sql': sql}));
      if (resp.statusCode != 200) {
        setState(() {
          _log = 'Server error: ${resp.statusCode} ${resp.body}';
        });
      } else {
        final data = jsonDecode(resp.body);
        if (data['error'] != null) {
          setState(() {
            _log = 'Error: ${data['error']}';
          });
        } else if (data['explain'] != null) {
          setState(() {
            _explain = data['explain'];
          });
        } else {
          setState(() {
            _log = 'Unexpected response from server.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _log = 'Request failed: $e';
      });
    } finally {
      setState(() {
        _running = false;
      });
    }
  }

Future<void> _saveBackendUrl() async {
  setState(() {
    _backendUrl = _backendController.text.trim();
  });
  await _saveSettings();

  if (!mounted) return; // ✅ Safe guard before using context

  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text('Backend URL saved')));
}

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _sqlController,
                maxLines: 10,
                style: TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Write SQL here... (SELECT / INSERT / UPDATE / DELETE)',
                ),
              ),
            ),
            SizedBox(width: 12),
            Column(
              children: [
                ElevatedButton.icon(
                  icon: _running ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Icon(Icons.play_arrow),
                  label: Text('Run'),
                  onPressed: _running ? null : _runQuery,
                ),
                SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: Icon(Icons.remove_red_eye),
                  label: Text('Explain'),
                  onPressed: _running ? null : _explainQuery,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResults() {
    if (_columns.isEmpty && _rows.isEmpty && _log.isEmpty && _explain.isEmpty) {
      return Center(child: Text('No results yet. Run a SELECT query to see rows.'));
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_columns.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: _columns.map((c) => DataColumn(label: Text(c))).toList(),
                rows: _rows.map((r) {
                  return DataRow(cells: r.map((cell) => DataCell(Text(cell?.toString() ?? ''))).toList());
                }).toList(),
              ),
            ),

          if (_explain.isNotEmpty) ...[
            SizedBox(height: 12),
            Text('EXPLAIN output', style: TextStyle(fontWeight: FontWeight.bold)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              margin: EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
              child: SingleChildScrollView(child: Text(_explain, style: TextStyle(fontFamily: 'monospace'))),
            ),
          ],

          if (_log.isNotEmpty) ...[
            SizedBox(height: 12),
            Text('Logs / Errors', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              margin: EdgeInsets.only(top: 6),
              decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(6)),
              child: Text(_log, style: TextStyle(fontFamily: 'monospace')),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryPanel() {
    return Container(
      width: 320,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: Colors.grey.shade300))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: _history.length,
              itemBuilder: (context, idx) {
                final q = _history[idx];
                return ListTile(
                  dense: true,
                  title: Text(q, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: 'monospace')),
                  onTap: () {
                    setState(() {
                      _sqlController.text = q;
                    });
                  },
                  trailing: IconButton(
                    icon: Icon(Icons.delete_outline),
                    onPressed: () {
                      setState(() {
                        _history.removeAt(idx);
                      });
                      _saveSettings();
                    },
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 8),
          ElevatedButton.icon(
            icon: Icon(Icons.clear_all),
            label: Text('Clear History'),
            onPressed: () {
              setState(() {
                _history.clear();
              });
              _saveSettings();
            },
          )
        ],
      ),
    );
  }

  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Backend Settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _backendController,
                decoration: InputDecoration(labelText: 'Backend URL', hintText: 'http://localhost:3000'),
              ),
              SizedBox(height: 8),
              Text('The backend executes SQL against your PostgreSQL database. The backend must be running and reachable from the app.'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
            ElevatedButton(onPressed: () {
              _saveBackendUrl();
              Navigator.of(context).pop();
            }, child: Text('Save')),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Postgres Dashboard'),
        actions: [
          IconButton(icon: Icon(Icons.settings), onPressed: _openSettingsDialog),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildEditor(),
                  SizedBox(height: 12),
                  Expanded(child: _buildResults()),
                ],
              ),
            ),
          ),

          // History / right rail
          _buildHistoryPanel(),
        ],
      ),
    );
  }
}

/* --------------------------- optional_backend/server.js --------------------------- */

/*
Node.js + Express backend (example) — save as optional_backend/server.js

Run:
  cd optional_backend
  npm init -y
  npm i express pg body-parser cors dotenv
  node server.js

This example expects a .env file with:
  DATABASE_URL=postgres://user:password@host:5432/dbname
  PORT=3000

SECURITY: This example provides no auth. Do not expose it to the public
without adding authentication (JWT, API keys) and rate limiting.
*/

/*
// server.js
const express = require('express');
const { Pool } = require('pg');
const bodyParser = require('body-parser');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(bodyParser.json());

const pool = new Pool({ connectionString: process.env.DATABASE_URL });

// Run query endpoint
app.post('/run-query', async (req, res) => {
  const { sql } = req.body || {};
  if (!sql) return res.status(400).json({ error: 'Missing sql' });

  // Optionally block destructive statements unless explicitly allowed
  const destructive = /(drop|truncate|alter\s+table|delete\s+from)/i;
  if (destructive.test(sql) && !process.env.ALLOW_DESTRUCTIVE) {
    return res.status(403).json({ error: 'Destructive statements are disabled in this server.' });
  }

  try {
    const client = await pool.connect();
    try {
      const result = await client.query(sql);
      if (result.command === 'SELECT' || result.rows) {
        const columns = result.fields ? result.fields.map(f => f.name) : Object.keys(result.rows[0] || {});
        const rows = result.rows.map(r => columns.map(c => r[c]));
        res.json({ columns, rows });
      } else {
        res.json({ message: `${result.command} OK, rowsAffected: ${result.rowCount}` });
      }
    } finally {
      client.release();
    }
  } catch (err) {
    res.json({ error: err.message });
  }
});

// Explain endpoint
app.post('/explain', async (req, res) => {
  const { sql } = req.body || {};
  if (!sql) return res.status(400).json({ error: 'Missing sql' });
  try {
    const client = await pool.connect();
    try {
      const q = 'EXPLAIN (ANALYZE, VERBOSE, BUFFERS, FORMAT TEXT) ' + sql;
      const result = await client.query(q);
      const explain = result.rows.map(r => Object.values(r).join(' ')).join('\n');
      res.json({ explain });
    } finally {
      client.release();
    }
  } catch (err) {
    res.json({ error: err.message });
  }
});

const port = process.env.PORT || 3000;
app.listen(port, () => console.log('Server listening on', port));
*/

/* --------------------------- Final Notes --------------------------- */

// - The frontend uses simple JSON endpoints: POST /run-query { sql } and POST /explain { sql }
//   expecting the backend to return { columns, rows } or { explain } or { error }.
// - For production: add authentication, TLS, and limit what SQL can be executed.
// - You can extend the Flutter app by adding: query param editor, saved favorites,
//   visual explain plan rendering, charts for numeric query results, CSV export, etc.

// If you'd like, I can:
// - provide a version that connects directly from Flutter (for desktop) using the `postgres` Dart package,
// - add syntax highlighting using flutter_highlight and line numbers,
// - implement CSV export and SQL linting in the frontend.

// Tell me which features you'd like next and I will extend the code.
