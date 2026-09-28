import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_po_token.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  test('extractor args include mweb player and gvs po tokens', () {
    const PlaybackPoToken tokens = PlaybackPoToken(
      player: 'PLAYERTOKEN',
      gvs: 'GVSTOKEN',
      visitorData: 'VISITOR',
    );
    expect(
      YtdlpService.extractorArgsFor('mweb', poToken: tokens.extractorValue),
      'youtube:player_client=mweb;po_token=mweb.player+PLAYERTOKEN,mweb.gvs+GVSTOKEN',
    );
    expect(
      YtdlpService.extractorArgsFor('android,web'),
      'youtube:player_client=android,web',
    );
  });
}
