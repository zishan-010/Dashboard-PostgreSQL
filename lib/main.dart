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
      _history.remove(q);
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

    if (!mounted) return;

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
          _buildHistoryPanel(),
        ],
      ),
    );
  }
}
