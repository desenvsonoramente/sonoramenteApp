import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/audio_model.dart';

class AudioService {
  Future<List<AudioModel>> fetchByCategory(String category) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('audios')
        .where('category', isEqualTo: category)
        .get();

    return snapshot.docs
          .map((doc) => AudioModel.fromMap(doc.id, doc.data())).toList();
  }
}
