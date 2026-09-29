import 'package:flutter_test/flutter_test.dart';
import 'package:yxz_tube/data/models/playback_po_token.dart';
import 'package:yxz_tube/data/services/ytdlp_service.dart';

void main() {
  test('extractor args include mweb po tokens and visitor_data', () {
    const PlaybackPoToken tokens = PlaybackPoToken(
      player: 'PLAYERTOKEN',
      gvs: 'GVSTOKEN',
      visitorData: 'VISITOR',
    );
    expect(
      YtdlpService.extractorArgsFor(
        'mweb,android_vr,web_safari,web_embedded',
        poToken: tokens.extractorValue,
        visitorData: tokens.visitorData,
      ),
      'youtube:player_client=mweb,android_vr,web_safari,web_embedded;'
      'po_token=mweb.player+PLAYERTOKEN,mweb.gvs+GVSTOKEN;'
      'visitor_data=VISITOR',
    );
  });

  test('default client omits player_client override', () {
    expect(
      YtdlpService.extractorArgsFor('default'),
      'youtube:',
    );
    expect(
      YtdlpService.extractorArgsFor(''),
      'youtube:',
    );
  });

  test('incomplete mint is rejected via isComplete', () {
    expect(
      const PlaybackPoToken(
        player: 'P',
        gvs: 'G',
        visitorData: '',
      ).isComplete,
      isFalse,
    );
  });
}
