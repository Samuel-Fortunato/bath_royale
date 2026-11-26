/// Local accidental-upload guard; never server-side evidence of truth.
enum Provenance {
  demo('demo'),
  unclassifiedLegacy('unclassified_legacy'),
  userCreated('user_created'),
  remote('remote');

  final String value;
  const Provenance(this.value);
  static Provenance fromValue(String value) =>
      values.singleWhere((p) => p.value == value);

  /// New local children of remote catalogue entries are locally authored.
  Provenance get child => this == remote ? userCreated : this;

  /// Necessary provenance gate only. This does not authorize any upload.
  bool get allowsFutureUpload => this == userCreated;
}
