class UserModel {
  final String uid;
  final String email;
  final String nom;
  final String prenom;
  final String role; // 'medecin_principal', 'medecin', 'assistant'
  final String pinCode;
  final String? medecinPrincipalId; // Pour médecins et assistants
  final DateTime createdAt;

  UserModel({
    required this.uid,
    required this.email,
    required this.nom,
    required this.prenom,
    required this.role,
    required this.pinCode,
    this.medecinPrincipalId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'email': email,
      'nom': nom,
      'prenom': prenom,
      'role': role,
      'pinCode': pinCode,
      'medecinPrincipalId': medecinPrincipalId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  static UserModel fromMap(Map<String, dynamic> map) {
    return UserModel(
      uid: map['uid'],
      email: map['email'],
      nom: map['nom'],
      prenom: map['prenom'],
      role: map['role'],
      pinCode: map['pinCode'],
      medecinPrincipalId: map['medecinPrincipalId'],
      createdAt: DateTime.parse(map['createdAt']),
    );
  }
}