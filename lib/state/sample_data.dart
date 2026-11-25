import 'package:bath_royale/models/bathroom.dart';
import 'package:bath_royale/models/review.dart';
import '../models/tag_presentation.dart';

const localUserId = 'local-user';

const sampleBathrooms = [
  Bathroom(id: '0', name: 'DEM - 3º piso', createdBy: localUserId),
  Bathroom(id: '1', name: 'CP - Rés do Chão', createdBy: localUserId),
  Bathroom(id: '2', name: 'CP - 2º Piso', createdBy: localUserId),
  Bathroom(id: '3', name: 'Biblioteca', createdBy: localUserId),
  Bathroom(id: '4', name: 'CP - 3º Piso', createdBy: localUserId),
  Bathroom(id: '5', name: 'Nome de Teste', createdBy: localUserId),
];

List<Review> createSampleReviews() => [
  Review(
    id: "sample-0",
    visitId: "visit-0",
    bathroomId: "0",
    authorId: localUserId,
    createdAt: DateTime.utc(2026, 1, 1),
    rating: 4.7,
    paperAvailability: 2,
    hygiene: 4,
    comfort: 4,
    aesthetics: 1,
    comment: 'Exemplo fictício: uma pausa tranquila entre aulas.',
    tags: ["nice", "cozy", "dark"].map(ReviewTagData.legacy).toList(),
  ),
  Review(
    id: "sample-1",
    visitId: "visit-1",
    bathroomId: "1",
    authorId: localUserId,
    createdAt: DateTime.utc(2026, 1, 1),
    rating: 1.3,
    paperAvailability: 1,
    hygiene: 2,
    comfort: 0,
    aesthetics: 1,
    comment:
        'Exemplo fictício: faltava sabonete. As paredes têm personalidade.',
    tags: ["grafiti", "wtf", "no like"].map(ReviewTagData.legacy).toList(),
  ),
  Review(
    id: "sample-2",
    visitId: "visit-2",
    bathroomId: "2",
    authorId: localUserId,
    createdAt: DateTime.utc(2026, 1, 1),
    rating: 4.1,
    paperAvailability: 0,
    hygiene: 3,
    comfort: 2,
    aesthetics: 4,
    comment: 'Exemplo fictício: pequeno, mas com uma vista digna de postal.',
    tags: ["nice", "small", "great view"].map(ReviewTagData.legacy).toList(),
  ),
  Review(
    id: "sample-3",
    visitId: "visit-3",
    bathroomId: "3",
    authorId: localUserId,
    createdAt: DateTime.utc(2026, 1, 1),
    rating: 3,
    paperAvailability: 2,
    hygiene: 1,
    comfort: 2,
    aesthetics: 1,
    comment: 'Exemplo fictício: silêncio para pôr a leitura em dia.',
    tags: ["cozy", "sad but true", "noisy"].map(ReviewTagData.legacy).toList(),
  ),
  Review(
    id: "sample-4",
    visitId: "visit-4",
    bathroomId: "4",
    authorId: localUserId,
    createdAt: DateTime.utc(2026, 1, 1),
    rating: 4.1,
    paperAvailability: 2,
    hygiene: 3,
    comfort: 2,
    aesthetics: 4,
    comment: 'Exemplo fictício: valeu a pena subir as escadas.',
    tags: ["nice", "small", "great view"].map(ReviewTagData.legacy).toList(),
  ),
];
