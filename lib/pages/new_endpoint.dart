import 'package:flutter/material.dart';
import '../services/new_form.dart';

// Écran de formulaire pour ajouter/modifier un endpoint
class EndpointFormScreen extends StatefulWidget {
  final Endpoint? endpoint;

  const EndpointFormScreen({super.key, this.endpoint});

  @override
  _EndpointFormScreenState createState() => _EndpointFormScreenState();
}

class _EndpointFormScreenState extends State<EndpointFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  String _selectedMethod = 'GET';
  bool _isEnabled = true;

  final List<String> _methods = ['GET', 'POST'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.endpoint?.name ?? '');
    _urlController = TextEditingController(text: widget.endpoint?.url ?? '');
    _selectedMethod = widget.endpoint?.method ?? 'GET';
    _isEnabled = widget.endpoint?.isEnabled ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF2C3E50),
      appBar: AppBar(
        backgroundColor: Color(0xFF2C3E50),
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios, color: Colors.white),
        ),
        title: Text(
          widget.endpoint == null ? 'Nouvel Endpoint' : 'Modifier Endpoint',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                // Nom
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nom de l\'endpoint',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          hintText: 'Ex: User Login API',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Veuillez entrer un nom';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // URL
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'URL',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      TextFormField(
                        controller: _urlController,
                        decoration: InputDecoration(
                          hintText: 'https://api.example.com/login',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Veuillez entrer une URL';
                          }
                          if (!value.startsWith('http')) {
                            return 'L\'URL doit commencer par http:// ou https://';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Méthode HTTP
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Méthode HTTP',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedMethod,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: _methods.map((method) {
                          return DropdownMenuItem(
                            value: method,
                            child: Text(method),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedMethod = value!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // État activé/désactivé
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Endpoint activé',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      Switch(
                        value: _isEnabled,
                        onChanged: (value) {
                          setState(() {
                            _isEnabled = value;
                          });
                        },
                        activeColor: Color(0xFF26A69A),
                      ),
                    ],
                  ),
                ),
                
                SizedBox(height: 16),
                
                // Bouton sauvegarder
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saveEndpoint,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFF26A69A),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.endpoint == null ? 'Créer l\'endpoint' : 'Sauvegarder',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  _saveEndpoint() {
    if (_formKey.currentState!.validate()) {
      final endpoint = Endpoint(
        id: widget.endpoint?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: _nameController.text,
        url: _urlController.text,
        method: _selectedMethod,
        isEnabled: _isEnabled,
      );
      
      Navigator.pop(context, endpoint);
    }
  }
}