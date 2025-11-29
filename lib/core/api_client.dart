import 'dart:convert';
import 'package:http/http.dart' as http;
import 'supabase_client.dart';

class ApiClient {
  final String baseUrl;
  ApiClient({this.baseUrl = 'http://10.0.2.2:5000/api'});

  Map<String, String> _headers({bool auth = false}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (auth) {
      final uid = Supa.currentUserId;
      if (uid == null) {
        throw StateError('Not authenticated');
      }
      h['X-User-Id'] = uid;
    }
    return h;
  }

  // Helpers
  Uri _u(String p, [Map<String, dynamic>? q]) => Uri.parse('$baseUrl$p').replace(queryParameters: q?.map((k, v) => MapEntry(k, '$v')));
  dynamic _json(http.Response r) {
    if (r.statusCode >= 200 && r.statusCode < 300) {
      return r.body.isEmpty ? null : jsonDecode(r.body);
    }
    throw ApiException(r.statusCode, r.body);
  }

  // Content
  Future<List<dynamic>> getSkills() async {
    final r = await http.get(_u('/skills'));
    return List<dynamic>.from(_json(r));
  }

  Future<List<dynamic>> getPracticeSetsForSkill(String slug) async {
    final r = await http.get(_u('/skills/$slug/practice-sets'));
    final data = _json(r) as Map<String, dynamic>;
    return List<dynamic>.from(data['items'] as List);
  }

  Future<Map<String, dynamic>> getPracticeSet(String id) async {
    final r = await http.get(_u('/practice-sets/$id'));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<List<dynamic>> getQuestionsForPracticeSet(String id) async {
    final r = await http.get(_u('/practice-sets/$id/questions'));
    return List<dynamic>.from(_json(r));
  }

  // Practice
  Future<Map<String, dynamic>> createPracticeSession(String practiceSetId) async {
    final r = await http.post(_u('/practice-sessions'), headers: _headers(auth: true), body: jsonEncode({'practice_set_id': practiceSetId}));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> submitPracticeAnswer(String sessionId, {required String questionId, String? optionId, String? answerText}) async {
    final r = await http.post(
      _u('/practice-sessions/$sessionId/answers'),
      headers: _headers(auth: true),
      body: jsonEncode({'question_id': questionId, 'option_id': optionId, 'answer_text': answerText}),
    );
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> completePracticeSession(String sessionId, {int? timeTakenSeconds}) async {
    final r = await http.post(
      _u('/practice-sessions/$sessionId/complete'),
      headers: _headers(auth: true),
      body: jsonEncode({'time_taken_seconds': timeTakenSeconds}),
    );
    return Map<String, dynamic>.from(_json(r));
  }

  Future<List<dynamic>> getRecentPracticeSessions() async {
    final r = await http.get(_u('/practice-sessions/recent'), headers: _headers(auth: true));
    return List<dynamic>.from(_json(r));
  }

  // AI: Writing evaluations
  Future<Map<String, dynamic>> createWritingEvalForPractice(String practiceAnswerId, {double targetBand = 7.0}) async {
    final r = await http.post(
      _u('/writing-eval/practice/$practiceAnswerId'),
      headers: _headers(auth: true),
      body: jsonEncode({'target_band': targetBand}),
    );
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> createWritingEvalForExam(String examAnswerId, {double targetBand = 7.0}) async {
    final r = await http.post(
      _u('/writing-eval/exam/$examAnswerId'),
      headers: _headers(auth: true),
      body: jsonEncode({'target_band': targetBand}),
    );
    return Map<String, dynamic>.from(_json(r));
  }

  // AI: Speaking
  Future<Map<String, dynamic>> createSpeakingAttempt({
    required String questionId,
    required String audioPath,
    required int durationSeconds,
    required String mode, // 'practice' or 'exam'
    String? examSessionId,
    String? examSectionResultId,
  }) async {
    final body = <String, dynamic>{
      'question_id': questionId,
      'audio_path': audioPath,
      'duration_seconds': durationSeconds,
      'mode': mode,
      if (examSessionId != null) 'exam_session_id': examSessionId,
      if (examSectionResultId != null) 'exam_section_result_id': examSectionResultId,
    };
    final r = await http.post(_u('/speaking-attempts'), headers: _headers(auth: true), body: jsonEncode(body));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> createSpeakingEvaluation(String attemptId, {double targetBand = 7.0}) async {
    final r = await http.post(
      _u('/speaking-eval/$attemptId'),
      headers: _headers(auth: true),
      body: jsonEncode({'target_band': targetBand}),
    );
    return Map<String, dynamic>.from(_json(r));
  }

  // Exam
  Future<String> createExamSession() async {
    final r = await http.post(_u('/exam-sessions'), headers: _headers(auth: true));
    return (_json(r) as Map<String, dynamic>)['exam_session_id'] as String;
  }

  Future<String> startExamSection({required String examSessionId, required String skillSlug, required int totalQuestions}) async {
    final r = await http.post(_u('/exam-sections'), headers: _headers(auth: true), body: jsonEncode({'exam_session_id': examSessionId, 'skill_slug': skillSlug, 'total_questions': totalQuestions}));
    return (_json(r) as Map<String, dynamic>)['section_result_id'] as String;
  }

  Future<Map<String, dynamic>> submitExamAnswer({required String examSessionId, required String sectionResultId, required String questionId, String? optionId, String? answerText}) async {
    final r = await http.post(_u('/exam-answers'), headers: _headers(auth: true), body: jsonEncode({'exam_session_id': examSessionId, 'section_result_id': sectionResultId, 'question_id': questionId, 'option_id': optionId, 'answer_text': answerText}));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> completeExamSection(String sectionResultId, {required int timeTakenSeconds, required int totalQuestions}) async {
    final r = await http.post(_u('/exam-sections/$sectionResultId/complete'), headers: _headers(auth: true), body: jsonEncode({'time_taken_seconds': timeTakenSeconds, 'total_questions': totalQuestions}));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> completeExamSession(String examSessionId, {int? totalTimeSeconds}) async {
    final r = await http.post(_u('/exam-sessions/$examSessionId/complete'), headers: _headers(auth: true), body: jsonEncode({'total_time_seconds': totalTimeSeconds}));
    return Map<String, dynamic>.from(_json(r));
  }

  // Premium
  Future<List<dynamic>> getPlans() async {
    final r = await http.get(_u('/plans'));
    return List<dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> createPaymentSession(String planId) async {
    final r = await http.post(_u('/payments/session'), headers: _headers(auth: true), body: jsonEncode({'plan_id': planId}));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> confirmPaymentSession(String sessionId) async {
    final r = await http.post(_u('/payments/session/$sessionId/confirm'), headers: _headers(auth: true));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>?> getCurrentSubscription() async {
    final r = await http.get(_u('/subscriptions/current'), headers: _headers(auth: true));
    return Map<String, dynamic>.from(_json(r));
  }

  // Profile & content extras
  Future<Map<String, dynamic>> getMe() async {
    final r = await http.get(_u('/me'), headers: _headers(auth: true));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<Map<String, dynamic>> updateMe({String? fullName, int? bandGoal, String? avatarPath}) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName;
    if (bandGoal != null) body['band_goal'] = bandGoal;
    if (avatarPath != null) body['avatar_url'] = avatarPath;
    
    final r = await http.patch(_u('/me'), headers: _headers(auth: true), body: jsonEncode(body));
    return Map<String, dynamic>.from(_json(r));
  }

  Future<List<dynamic>> getFaqs() async {
    final r = await http.get(_u('/faqs'));
    return List<dynamic>.from(_json(r));
  }

  Future<List<dynamic>> getTestimonials() async {
    final r = await http.get(_u('/testimonials'));
    return List<dynamic>.from(_json(r));
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);
  @override
  String toString() => 'ApiException($statusCode): $body';
}
