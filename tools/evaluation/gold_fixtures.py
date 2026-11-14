"""Materialize synthetic timelines without implying real recorded audio or model outcomes."""
import json
from pathlib import Path
import uuid


def load():
    spec = json.loads((Path(__file__).parent / 'fixtures/understanding-gold.json').read_text())
    cases = []
    for case in spec['cases']:
        case = dict(case)
        turns = case.get('turns')
        if case.get('scenario') == 'duration':
            count = case['minutes'] * case['turnsPerMinute']
            turns = [['進行', f'検証項目{i + 1}の観測値は{i + 100}msです。これは測定報告であり公開承認ではありません。条件を変えた比較を続けます。'] for i in range(count)]
            turns[0] = ['責任者', '当初は11月20日に公開すると決定しました。予算は150万円です。']
            turns[count // 2] = ['開発', '負荷試験で障害が見つかりました。公開は再検討が必要です。']
            turns[-1] = ['責任者', '当初の公開決定を撤回します。性能試験と監査承認が終わるまで公開しません。']
            case['gold'] = [
                {'id':'budget','category':'facts','quote':'予算は150万円です。','speaker':'責任者'},
                {'id':'failure','category':'facts','quote':'負荷試験で障害が見つかりました。','speaker':'開発'},
                {'id':'final','category':'decisions','quote':turns[-1][1],'speaker':'責任者'}]
            case['forbiddenFinalDecisions'] = ['11月20日に公開する']
        step = 60 / case.get('turnsPerMinute', 6)
        case['transcript'] = [{'id':str(uuid.uuid5(uuid.NAMESPACE_URL, 'memora-test:'+case['id']+':'+str(i))),
                              'speaker': speaker, 'text':text, 'timestamp':i * step}
                             for i, (speaker, text) in enumerate(turns)]
        for fact in case['gold']:
            matches = [s for s in case['transcript'] if fact['quote'] in s['text'] and fact['speaker'] == s['speaker']]
            assert len(matches) == 1, (case['id'], fact['id'])
            fact['sourceSegmentID'] = matches[0]['id']
        cases.append(case)
    return cases
