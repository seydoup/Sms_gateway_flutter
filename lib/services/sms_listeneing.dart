import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'new_form.dart';
import 'sms_history.dart';

@pragma("vm:entry-point")
class SmsService {
  static final Telephony telephony = Telephony.instance;
  static bool _isListening = false;

  // Vérifier s'il y a des endpoints configurés et actifs
  static Future<bool> hasActiveEndpoints() async {
    final activeEndpoints = await _getActiveEndpoints();
    return activeEndpoints.isNotEmpty;
  }

  // Démarrer l'écoute des SMS seulement s'il y a des endpoints actifs
  static Future<bool> startSmsListening() async {
    try {
      // Vérifier s'il y a des endpoints actifs
      if (!(await hasActiveEndpoints())) {
        print("Aucun endpoint actif - écoute SMS non démarrée");
        await stopSmsListening();
        return false;
      }

      // Vérifier si déjà en écoute
      if (_isListening) {
        print("Écoute SMS déjà active");
        return true;
      }

      // Demander les permissions
      final bool? permissionsGranted = await telephony.requestPhoneAndSmsPermissions;
      
      if (permissionsGranted != null && permissionsGranted) {
        // Démarrer l'écoute des SMS
        telephony.listenIncomingSms(
          onNewMessage: _handleIncomingSms,
          onBackgroundMessage: _handleBackgroundSms,
          listenInBackground: true,
        );
        
        _isListening = true;
        print("Écoute SMS démarrée avec succès");
        return true;
      } else {
        print("Permissions SMS refusées");
        return false;
      }
    } catch (e) {
      print("Erreur lors du démarrage de l'écoute SMS: $e");
      return false;
    }
  }

  // Arrêter l'écoute des SMS
  static Future<void> stopSmsListening() async {
    try {
      if (_isListening) {
        // Note: Telephony ne fournit pas de méthode stop explicite
        // L'écoute s'arrête automatiquement quand l'app est fermée
        _isListening = false;
        print("Écoute SMS arrêtée");
      }
    } catch (e) {
      print("Erreur lors de l'arrêt de l'écoute SMS: $e");
    }
  }

  // Redémarrer l'écoute si nécessaire (appelé après modification des endpoints)
  static Future<void> refreshSmsListening() async {
    if (await hasActiveEndpoints()) {
      if (!_isListening) {
        await startSmsListening();
      }
    } else {
      await stopSmsListening();
    }
  }

  // Gestionnaire pour les SMS en arrière-plan - DOIT être une fonction statique top-level
  @pragma("vm:entry-point")
  static _handleBackgroundSms(SmsMessage message) {
    print("SMS reçu en arrière-plan: ${message.body}");
    _processSmsMessage(message);
  }

  // Gestionnaire pour les SMS en premier plan
  static _handleIncomingSms(SmsMessage message) {
    print("SMS reçu en premier plan: ${message.body} de ${message.address}");
    _processSmsMessage(message);
  }

  // Traiter le message SMS et l'envoyer aux endpoints actifs
  static Future<Map<dynamic, dynamic>> _processSmsMessage(SmsMessage message) async {
    Map<String,dynamic> smsData = {};
    List<Endpoint> activeEndpoints;
    List<EndpointResult> endpointResults = [];
    
    try {
      // Charger les endpoints actifs
      activeEndpoints = await _getActiveEndpoints();
      
      if (activeEndpoints.isEmpty) {
        print("Aucun endpoint actif - SMS ignoré");
        return {};
      }

      // Préparer les données du SMS
      smsData = {
        'sender': message.address ?? 'Inconnu',
        'content': message.body ?? '',
        'timestamp': DateTime.now().toIso8601String(),
      };

      print("Envoi du SMS vers ${activeEndpoints.length} endpoint(s) actif(s)");

      // Envoyer le SMS à chaque endpoint actif et collecter les résultats
      for (final endpoint in activeEndpoints) {
        final success = await _sendSmsToEndpoint(endpoint, smsData);
        
        endpointResults.add(EndpointResult(
          endpointName: endpoint.name,
          endpointUrl: endpoint.url,
          status: success ? 'success' : 'error',
          method: endpoint.method,
        ));
      }

      // Sauvegarder dans l'historique
      await _saveToHistory(
        senderAddress: message.address ?? 'Inconnu',
        date: smsData['timestamp'],
        endpointResults: endpointResults,
      );

    } catch (e) {
      print("Erreur lors du traitement du SMS: $e");
    }

    return {
      'senderaddr': smsData['sender'],
      'smsdate': smsData['timestamp'],
      'activeendp': await _getActiveEndpoints(),
      'results': endpointResults,
    };
  }

  // Envoyer les données SMS à un endpoint spécifique
  static Future<bool> _sendSmsToEndpoint(Endpoint endpoint, Map<String, dynamic> smsData) async {
    try {
      print("Envoi vers ${endpoint.name} (${endpoint.method}) : ${endpoint.url}");

      final headers = {
        'Content-Type': 'application/json',
        'User-Agent': 'SMS-Forwarder-Flutter/1.0',
      };

      http.Response? response;
      final jsonBody = jsonEncode(smsData);

      // Envoyer selon la méthode HTTP configurée
      switch (endpoint.method.toUpperCase()) {
        case 'GET':
          // Pour GET, on peut passer les données en query parameters
          final uri = Uri.parse(endpoint.url).replace(
            queryParameters: smsData.map((key, value) => MapEntry(key, value.toString()))
          );
          response = await http.get(uri, headers: headers).timeout(Duration(seconds: 30));
          break;

        case 'POST':
          response = await http.post(
            Uri.parse(endpoint.url),
            headers: headers,
            body: jsonBody,
          ).timeout(Duration(seconds: 30));
          break;

        default:
          print("Méthode HTTP non supportée: ${endpoint.method}");
          return false;
      }
      
      // Vérifier si la requête est bien parvenue
      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Requête réussie
        print('Succès: ${response.statusCode}');
        return true;
      } else {
        // Erreur HTTP
        print('Erreur HTTP: ${response.statusCode}');
        print('Message: ${response.body}');
        return false;
      }

    } catch (e) {
      print("❌ Erreur lors de l'envoi vers ${endpoint.name}: $e");
      return false;
    }
  }

  // Sauvegarder un élément dans l'historique
  static Future<void> _saveToHistory({
    required String senderAddress,
    required String date,
    required List<EndpointResult> endpointResults,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Générer un ID unique pour cet élément
      final id = DateTime.now().millisecondsSinceEpoch.toString();
      
      // Créer l'élément d'historique
      final historyItem = HistoryItem(
        id: id,
        senderAddress: senderAddress,
        date: date,
        endpoints: endpointResults,
      );

      // Charger l'historique existant
      final existingHistory = await getHistory();
      
      // Ajouter le nouvel élément au début de la liste
      existingHistory.insert(0, historyItem);
      
      // Limiter l'historique à 100 éléments maximum
      if (existingHistory.length > 100) {
        existingHistory.removeRange(100, existingHistory.length);
      }
      
      // Sauvegarder l'historique mis à jour
      final historyJson = existingHistory.map((item) => jsonEncode(item.toJson())).toList();
      await prefs.setStringList('sms_history', historyJson);
      
      print("Historique sauvegardé: ${historyItem.senderAddress} -> ${endpointResults.length} endpoints");
      
    } catch (e) {
      print("Erreur lors de la sauvegarde de l'historique: $e");
    }
  }

  // Récupérer l'historique complet
  static Future<List<HistoryItem>> getHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getStringList('sms_history') ?? [];
      
      print("[SmsService] getHistory finished");
      return historyJson
          .map((json) => HistoryItem.fromJson(jsonDecode(json)))
          .toList();
    } catch (e) {
      print("Erreur lors du chargement de l'historique: $e");
      return [];
    }
  }

  // Effacer l'historique
  static Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sms_history');
      print("Historique effacé");
    } catch (e) {
      print("Erreur lors de l'effacement de l'historique: $e");
    }
  }

  // Charger les endpoints actifs depuis SharedPreferences
  static Future<List<Endpoint>> _getActiveEndpoints() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final endpointsJson = prefs.getStringList('endpoints') ?? [];
      
      final allEndpoints = endpointsJson
          .map((json) => Endpoint.fromJson(jsonDecode(json)))
          .toList();
      
      // Retourner seulement les endpoints actifs
      return allEndpoints.where((endpoint) => endpoint.isEnabled).toList();
    } catch (e) {
      print("Erreur lors du chargement des endpoints: $e");
      return [];
    }
  }

  // Méthodes utilitaires publiques
  static bool get isListening => _isListening;

  // Obtenir le statut du service
  static Future<Map<String, dynamic>> getServiceStatus() async {
    final activeEndpoints = await _getActiveEndpoints();
    final historyCount = (await getHistory()).length;
    
    return {
      'isListening': _isListening,
      'activeEndpointsCount': activeEndpoints.length,
      'hasPermissions': await telephony.requestPhoneAndSmsPermissions,
      'historyCount': historyCount,
    };
  }
}

// Gestionnaire global pour les SMS en arrière-plan
// OBLIGATOIRE: Cette fonction doit être au niveau top-level (pas dans une classe)
@pragma('vm:entry-point')
void backgroundSmsHandler(SmsMessage message) {
  print("Gestionnaire d'arrière-plan global appelé");
  SmsService._handleBackgroundSms(message);
}