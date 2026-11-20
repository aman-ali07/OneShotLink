import { Bar, Card, Stage, Text, Window } from '../../kit'
import './card.css'

// OneShotLink product still. The window is the app's open screen, cropped hard
// on the right and bottom; the revealed-value card straddles its right edge as
// a satellite. Real words carry the story; everything else is filler.
const LINES = [
  { label: 'Kind', value: 'text' },
  { label: 'Expires after', value: '1 day' },
  { label: 'Passphrase', value: 'none' },
]

export default function OneShotLinkStill() {
  return (
    <Stage width={720} height={340} compact={{ below: 400, width: 358, height: 300 }} className="osl-stage">
      {() => (
        <>
          <Window url="app.oneshotlink.com/secret/k3x9…" className="osl-window">
            <div className="osl-body">
              <div className="osl-eyebrow">03 / OPEN</div>
              <Text className="osl-title">A secret was shared with you</Text>
              <Text className="osl-sub">It can be opened once. Opening it deletes it.</Text>
              <div className="osl-notice">
                <Text>Do not reload after revealing. The value cannot be shown again.</Text>
              </div>
              <div className="osl-fields">
                <div className="osl-field">
                  <Text className="osl-label">Kind</Text>
                  <Text className="osl-value">text</Text>
                </div>
              </div>
              <div className="osl-cta">Reveal secret</div>
            </div>
          </Window>

          <Card className="osl-result" lift pad="large" gap={10}>
            <div className="osl-result-top">
              <span className="osl-dot" aria-hidden="true" />
              <Text className="osl-result-eyebrow">SHOWN ONCE</Text>
            </div>
            <Text className="osl-result-value">correct-horse-battery</Text>
            <div className="osl-result-rule" />
            <div className="osl-result-foot">
              <Text>Deleted on the server.</Text>
            </div>
          </Card>
        </>
      )}
    </Stage>
  )
}
