# frozen_string_literal: true

require "ulid"

module Websites
  # Curated https photography for marketing layouts. Blank media is filled.
  # The shared stock set is replaced once when a layout palette has its own
  # shot. Owner-authored URLs outside that set are left alone.
  module Media
    HOST = "https://images.unsplash.com"

    class << self
      def shot(id, width: 1800)
        "#{HOST}/#{id}?auto=format&fit=crop&w=#{width}&q=80"
      end
    end

    HERO_CINEMATIC = shot("photo-1600210492486-724fe5c67fb0")
    HERO_SPLIT     = shot("photo-1497366216548-37526070297c")
    SPLIT          = shot("photo-1600566753190-17f0baa2a6c3")
    FEATURES = [
      shot("photo-1600607687939-ce8a6c25118c"),
      shot("photo-1497366811353-6870744d04b2"),
      shot("photo-1486406146926-c627a92ad1ab")
    ].freeze
    CARDS = [
      shot("photo-1441986300917-64674bd600d8", width: 1200),
      shot("photo-1517245386807-bb43f82c33c4", width: 1200),
      shot("photo-1469474968028-56623f02e42e", width: 1200)
    ].freeze
    BENTO_HERO = shot("photo-1501785888041-af3ef285b470")
    BENTO_WIDE = shot("photo-1500530855697-b586d89ba3ee", width: 1400)
    BENTO_UNITS = [
      shot("photo-1511818966892-d7d671e672a2", width: 900),
      shot("photo-1524758631624-e2822e304c36", width: 900)
    ].freeze
    PORTRAITS = [
      shot("photo-1494790108377-be9c29b29330", width: 800),
      shot("photo-1507003211169-0a1dd7228f2d", width: 800),
      shot("photo-1438761681033-6461ffad8d80", width: 800),
      shot("photo-1500648767791-00dcc994a43e", width: 800)
    ].freeze
    DEAD_IDS = %w[
      photo-1497215728101-856f4ea42187
      photo-1600607687644-c7171b42498b
      photo-1600047509807-ba8f99d2cdbc
      photo-1461896836934-ffe607ba6851
      photo-1517649763962-0c623066027b
      photo-1498243691581-b145c5f54a5a
      photo-1523050854058-8df90110c9f1
    ].freeze
    # Auto-filled stock. Replaced once when a layout palette assigns a different shot.
    STOCK_IDS = %w[
      photo-1600210492486-724fe5c67fb0
      photo-1497366216548-37526070297c
      photo-1600566753190-17f0baa2a6c3
      photo-1600607687939-ce8a6c25118c
      photo-1497366811353-6870744d04b2
      photo-1486406146926-c627a92ad1ab
      photo-1441986300917-64674bd600d8
      photo-1517245386807-bb43f82c33c4
      photo-1469474968028-56623f02e42e
      photo-1501785888041-af3ef285b470
      photo-1500530855697-b586d89ba3ee
      photo-1511818966892-d7d671e672a2
      photo-1524758631624-e2822e304c36
      photo-1494790108377-be9c29b29330
      photo-1507003211169-0a1dd7228f2d
      photo-1438761681033-6461ffad8d80
      photo-1500648767791-00dcc994a43e
    ].freeze

    # Distinct photography per starter. Ids here are not in STOCK_IDS, so a
    # catalog sync replaces the shared stock set once and then leaves it.
    PALETTE_SHOTS = {
      "presence" => {
        hero: "photo-1600585154340-be6161a56a0c",
        split: "photo-1600607688969-a5bfcd646154",
        chapter: "photo-1600566753086-00f18fb6b3ea",
        features: %w[photo-1600210492493-0946911123ea photo-1600121848594-d8644e57abab photo-1600566753151-384129cf4e3e],
        cards: %w[photo-1600585154526-990dced4db0d photo-1600573472592-401b489a3cdc photo-1600566752355-35792bedcfea],
        bento_hero: "photo-1600210492486-724fe5c67fb0",
        bento_wide: "photo-1600607687920-4e2a09cf159d",
        bento_units: %w[photo-1600585152220-90363fe7e115 photo-1600566753376-12c8ab7fb75b],
        portraits: %w[photo-1544005313-94ddf0286df2 photo-1506794778202-cad84cf45f1d photo-1531123897727-8f129e1688ce photo-1507591064344-4c6ce005b128]
      },
      "saas" => {
        hero: "photo-1551434678-e076c223a692",
        split: "photo-1497366216548-37526070297c",
        chapter: "photo-1522071820081-009f0129c71c",
        features: %w[photo-1460925895917-afdab827c52f photo-1551288049-bebda4e38f71 photo-1553877522-43269d4ea984],
        cards: %w[photo-1556761175-5973dc0f32e7 photo-1600880292203-757bb62b4baf photo-1552664730-d307ca884978],
        bento_hero: "photo-1551434678-e076c223a692",
        bento_wide: "photo-1460925895917-afdab827c52f",
        bento_units: %w[photo-1551288049-bebda4e38f71 photo-1517245386807-bb43f82c33c4],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7 photo-1580489944761-15a19d654956 photo-1472099645785-5658abf4ff4e]
      },
      "cinematic" => {
        hero: "photo-1618221195710-dd6b41faaea6",
        split: "photo-1616486338812-3dadae4b4ace",
        chapter: "photo-1600210492486-724fe5c67fb0",
        features: %w[photo-1618220179428-22790b461013 photo-1615873968403-89e068629265 photo-1616137422495-1e9e46e2aa77],
        cards: %w[photo-1615874694520-474822394e73 photo-1586023492125-27b2c045efd7 photo-1567016432779-094069958ea5],
        bento_hero: "photo-1493663284031-b7e3aefcae8e",
        bento_wide: "photo-1616486338812-3dadae4b4ace",
        bento_units: %w[photo-1615873968403-89e068629265 photo-1618220179428-22790b461013],
        portraits: %w[photo-1534528741775-53994a69daeb photo-1507003211169-0a1dd7228f2d photo-1524504388940-b1c1722653e1 photo-1500648767791-00dcc994a43e]
      },
      "editorial" => {
        hero: "photo-1552674605-db6ffd4facb5",
        split: "photo-1517836357463-d25dfeac3438",
        chapter: "photo-1530143311094-34d807799e8f",
        features: %w[photo-1476480862126-209bfaa8edc8 photo-1571019614242-c5c5dee9f50b photo-1518611012118-696072aa579a],
        cards: %w[photo-1552674605-db6ffd4facb5 photo-1517836357463-d25dfeac3438 photo-1530143311094-34d807799e8f],
        bento_hero: "photo-1552674605-db6ffd4facb5",
        bento_wide: "photo-1530143311094-34d807799e8f",
        bento_units: %w[photo-1517836357463-d25dfeac3438 photo-1571019614242-c5c5dee9f50b],
        portraits: %w[photo-1524504388940-b1c1722653e1 photo-1539571696357-5a69c17a67c6 photo-1488426862026-3ee34a7d66df photo-1506794778202-cad84cf45f1d]
      },
      "studio" => {
        hero: "photo-1502672260266-1c1ef2d93688",
        split: "photo-1522708323590-d24dbb6b0267",
        chapter: "photo-1560448204-e02f11c3d0e2",
        features: %w[photo-1505693416388-ac5ce068fe85 photo-1493809842364-78817add7ffb photo-1484154218962-a197022b5858],
        cards: %w[photo-1502672260266-1c1ef2d93688 photo-1522708323590-d24dbb6b0267 photo-1560448204-e02f11c3d0e2],
        bento_hero: "photo-1502672260266-1c1ef2d93688",
        bento_wide: "photo-1560448204-e02f11c3d0e2",
        bento_units: %w[photo-1505693416388-ac5ce068fe85 photo-1493809842364-78817add7ffb],
        portraits: %w[photo-1544005313-94ddf0286df2 photo-1507591064344-4c6ce005b128 photo-1524504388940-b1c1722653e1 photo-1506794778202-cad84cf45f1d],
        listings: %w[photo-1510798831971-661eb04b3739 photo-1518780664697-55e3ad937233 photo-1499793983690-e29da59ef1c2
                     photo-1502672260266-1c1ef2d93688 photo-1542718610-a1d656d1884c photo-1560448204-e02f11c3d0e2
                     photo-1449158743715-0a90ebb6d2d8 photo-1564013799919-ab600027ffc6]
      },
      "product" => {
        hero: "photo-1498050108023-c5249f4df085",
        split: "photo-1519389950473-47ba0277781c",
        chapter: "photo-1517245386807-bb43f82c33c4",
        features: %w[photo-1553877522-43269d4ea984 photo-1600880292203-757bb62b4baf photo-1552664730-d307ca884978],
        cards: %w[photo-1498050108023-c5249f4df085 photo-1519389950473-47ba0277781c photo-1551288049-bebda4e38f71],
        bento_hero: "photo-1498050108023-c5249f4df085",
        bento_wide: "photo-1460925895917-afdab827c52f",
        bento_units: %w[photo-1551288049-bebda4e38f71 photo-1517245386807-bb43f82c33c4],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1560250097-0b93528c311a photo-1580489944761-15a19d654956 photo-1519085360753-af0119f7cbe7]
      },
      "ledger" => {
        hero: "photo-1563013544-824ae1b704d3",
        split: "photo-1556742049-0cfed4f6a45d",
        chapter: "photo-1554224155-8d04cb21cd6c",
        features: %w[photo-1556740738-b6a63e27c4df photo-1563013544-824ae1b704d3 photo-1554224155-6726b3ff858f],
        cards: %w[photo-1556742049-0cfed4f6a45d photo-1563013544-824ae1b704d3 photo-1554224155-8d04cb21cd6c],
        bento_hero: "photo-1486406146926-c627a92ad1ab",
        bento_wide: "photo-1460925895917-afdab827c52f",
        bento_units: %w[photo-1551288049-bebda4e38f71 photo-1554224155-6726b3ff858f],
        portraits: %w[photo-1573497019940-1c28c88b4f3e photo-1560250097-0b93528c311a photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7]
      },
      "signal" => {
        hero: "photo-1451187580459-43490279c0fa",
        split: "photo-1518770660439-4636190af475",
        chapter: "photo-1550751827-4bd374c3f58b",
        features: %w[photo-1518770660439-4636190af475 photo-1550751827-4bd374c3f58b photo-1451187580459-43490279c0fa],
        cards: %w[photo-1550745165-9bc0b252726f photo-1518770660439-4636190af475 photo-1519389950473-47ba0277781c],
        bento_hero: "photo-1451187580459-43490279c0fa",
        bento_wide: "photo-1550751827-4bd374c3f58b",
        bento_units: %w[photo-1518770660439-4636190af475 photo-1550745165-9bc0b252726f],
        portraits: %w[photo-1539571696357-5a69c17a67c6 photo-1524504388940-b1c1722653e1 photo-1506794778202-cad84cf45f1d photo-1544005313-94ddf0286df2]
      },
      "atelier" => {
        hero: "photo-1611930022073-b7a4ba5fcccd",
        split: "photo-1556228720-195a672e8a03",
        chapter: "photo-1570172619644-dfd03ed5d881",
        features: %w[photo-1608248543803-ba4f8c70ae0b photo-1596462502278-27bfdc403348 photo-1611930022073-b7a4ba5fcccd],
        cards: %w[photo-1556228720-195a672e8a03 photo-1570172619644-dfd03ed5d881 photo-1608248543803-ba4f8c70ae0b],
        bento_hero: "photo-1611930022073-b7a4ba5fcccd",
        bento_wide: "photo-1556228720-195a672e8a03",
        bento_units: %w[photo-1570172619644-dfd03ed5d881 photo-1608248543803-ba4f8c70ae0b],
        portraits: %w[photo-1531123897727-8f129e1688ce photo-1534528741775-53994a69daeb photo-1524504388940-b1c1722653e1 photo-1506794778202-cad84cf45f1d],
        places: %w[photo-1528698827591-e19ccd7bc23d photo-1519710164239-da123dc03ef4 photo-1558997519-83ea9252edf8]
      },
      "campus" => {
        hero: "photo-1541339907198-e08756dedf3f",
        split: "photo-1562774053-701939374585",
        chapter: "photo-1524178232363-1fb2b075b655",
        features: %w[photo-1427504494785-3a9ca7044f45 photo-1541339907198-e08756dedf3f photo-1562774053-701939374585],
        cards: %w[photo-1427504494785-3a9ca7044f45 photo-1524178232363-1fb2b075b655 photo-1523580494863-6f3031224c94],
        bento_hero: "photo-1541339907198-e08756dedf3f",
        bento_wide: "photo-1562774053-701939374585",
        bento_units: %w[photo-1524178232363-1fb2b075b655 photo-1427504494785-3a9ca7044f45],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1507003211169-0a1dd7228f2d photo-1580489944761-15a19d654956 photo-1472099645785-5658abf4ff4e]
      },
      "gazette" => {
        hero: "photo-1504711434969-e33886168f5c",
        split: "photo-1495020689067-958852a7765e",
        chapter: "photo-1455390582262-044cdead277a",
        features: %w[photo-1486312338219-ce68d2c6f44d photo-1478720568477-152d9b164e26 photo-1504711434969-e33886168f5c],
        cards: %w[photo-1504711434969-e33886168f5c photo-1495020689067-958852a7765e photo-1455390582262-044cdead277a],
        bento_hero: "photo-1504711434969-e33886168f5c",
        bento_wide: "photo-1495020689067-958852a7765e",
        bento_units: %w[photo-1455390582262-044cdead277a photo-1486312338219-ce68d2c6f44d],
        portraits: %w[photo-1544005313-94ddf0286df2 photo-1506794778202-cad84cf45f1d photo-1531123897727-8f129e1688ce photo-1507591064344-4c6ce005b128],
        stories: %w[photo-1494412574643-ff11b0a5c1c3 photo-1504328345606-18bbc8c9d7d1 photo-1495020689067-958852a7765e
                    photo-1507842217343-583bb7270b66 photo-1524995997946-a1c2e315a42f photo-1504711434969-e33886168f5c]
      },
      "lumen" => {
        hero: "photo-1639322537228-f710d846310a",
        split: "photo-1620641788421-7a1c342ea42e",
        chapter: "photo-1618005182384-a83a8bd57fbe",
        features: %w[photo-1614850523459-c2f4c699c52e photo-1557672172-298e090bd0f1 photo-1579546929518-9e396f3cc809],
        cards: %w[photo-1555066931-4365d14bab8c photo-1633356122544-f134324a6cee photo-1504384308090-c894fdcc538d],
        bento_hero: "photo-1639322537228-f710d846310a",
        bento_wide: "photo-1620641788421-7a1c342ea42e",
        bento_units: %w[photo-1618005182384-a83a8bd57fbe photo-1614850523459-c2f4c699c52e],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7 photo-1580489944761-15a19d654956 photo-1472099645785-5658abf4ff4e]
      },
      "monograph" => {
        hero: "photo-1484101403633-562f891dc89a",
        split: "photo-1493663284031-b7e3aefcae8e",
        chapter: "photo-1513519245088-0e12902e5a38",
        features: %w[photo-1495474472287-4d71bcdd2085 photo-1517705008128-361805f42e86 photo-1449247709967-d4461a6a6103],
        cards: %w[photo-1490481651871-ab68de25d43d photo-1466637574441-749b8f19452f photo-1493663284031-b7e3aefcae8e],
        bento_hero: "photo-1484101403633-562f891dc89a",
        bento_wide: "photo-1513519245088-0e12902e5a38",
        bento_units: %w[photo-1495474472287-4d71bcdd2085 photo-1517705008128-361805f42e86],
        portraits: %w[photo-1544005313-94ddf0286df2 photo-1506794778202-cad84cf45f1d photo-1531123897727-8f129e1688ce photo-1507591064344-4c6ce005b128]
      },
      "terrain" => {
        hero: "photo-1464822759023-fed622ff2c3b",
        split: "photo-1501555088652-021faa106b9b",
        chapter: "photo-1454496522488-7a8e488e8606",
        features: %w[photo-1551632811-561732d1e306 photo-1478131143081-80f7f84ca84d photo-1504280390367-361c6d9f38f4],
        cards: %w[photo-1486870591958-9b9d0d1dda99 photo-1519681393784-d120267933ba photo-1506905925346-21bda4d32df4],
        bento_hero: "photo-1506905925346-21bda4d32df4",
        bento_wide: "photo-1470071459604-3b5ec3a7fe05",
        bento_units: %w[photo-1447752875215-b2761acb3c5d photo-1500534314209-a25ddb2bd429],
        portraits: %w[photo-1539571696357-5a69c17a67c6 photo-1524504388940-b1c1722653e1 photo-1506794778202-cad84cf45f1d photo-1544005313-94ddf0286df2]
      },
      "supper" => {
        hero: "photo-1414235077428-338989a2e8c0",
        split: "photo-1517248135467-4c7edcad34c4",
        chapter: "photo-1559339352-11d035aa65de",
        features: %w[photo-1504674900247-0877df9cc836 photo-1540189549336-e6e99c3679fe photo-1476224203421-9ac39bcb3327],
        cards: %w[photo-1592861956120-e524fc739696 photo-1600891964599-f61ba0e24092 photo-1424847651672-bf20a4b0982b],
        bento_hero: "photo-1414235077428-338989a2e8c0",
        bento_wide: "photo-1559339352-11d035aa65de",
        bento_units: %w[photo-1504674900247-0877df9cc836 photo-1592861956120-e524fc739696],
        portraits: %w[photo-1534528741775-53994a69daeb photo-1507003211169-0a1dd7228f2d photo-1524504388940-b1c1722653e1 photo-1500648767791-00dcc994a43e]
      },
      "clinic" => {
        hero: "photo-1576091160399-112ba8d25d1d",
        split: "photo-1631217868264-e5b90bb7e133",
        chapter: "photo-1519494026892-80bbd2d6fd0d",
        features: %w[photo-1579684385127-1ef15d508118 photo-1584982751601-97dcc096659c photo-1631217868264-e5b90bb7e133],
        cards: %w[photo-1519494026892-80bbd2d6fd0d photo-1576091160399-112ba8d25d1d photo-1579684385127-1ef15d508118],
        bento_hero: "photo-1631217868264-e5b90bb7e133",
        bento_wide: "photo-1519494026892-80bbd2d6fd0d",
        bento_units: %w[photo-1584982751601-97dcc096659c photo-1579684385127-1ef15d508118],
        portraits: %w[photo-1622253692010-333f2da6031d photo-1612349317150-e413f6a5b16d photo-1559839734-2b71ea197ec2 photo-1582750433449-648ed127bb54]
      },
      "folio" => {
        hero: "photo-1545239351-1141bd82e8a6",
        split: "photo-1558655146-9f40138edfeb",
        chapter: "photo-1561070791-2526d30994b5",
        features: %w[photo-1494438639946-1ebd1d20bf85 photo-1541701494587-cb58502866ab photo-1550684848-fac1c5b4e853],
        cards: %w[photo-1507608616759-54f48f0af0ee photo-1586717791821-3f44a563fa4c photo-1558655146-9f40138edfeb],
        bento_hero: "photo-1545239351-1141bd82e8a6",
        bento_wide: "photo-1487958449943-2429e8be8625",
        bento_units: %w[photo-1541701494587-cb58502866ab photo-1494438639946-1ebd1d20bf85],
        portraits: %w[photo-1531123897727-8f129e1688ce photo-1507591064344-4c6ce005b128 photo-1544005313-94ddf0286df2 photo-1506794778202-cad84cf45f1d]
      },
      "voyage" => {
        hero: "photo-1566073771259-6a8506099945",
        split: "photo-1582719478250-c89cae4dc85b",
        chapter: "photo-1520250497591-112f2f40a3f4",
        features: %w[photo-1571896349842-33c89424de2d photo-1445019980597-93fa8acb246c photo-1584132967334-10e028bd69f7],
        cards: %w[photo-1542314831-068cd1dbfeeb photo-1551882547-ff40c63fe5fa photo-1540541338287-41700207dee6],
        bento_hero: "photo-1540541338287-41700207dee6",
        bento_wide: "photo-1566073771259-6a8506099945",
        bento_units: %w[photo-1582719478250-c89cae4dc85b photo-1584132967334-10e028bd69f7],
        portraits: %w[photo-1534528741775-53994a69daeb photo-1507003211169-0a1dd7228f2d photo-1524504388940-b1c1722653e1 photo-1500648767791-00dcc994a43e]
      },
      "kinetic" => {
        hero: "photo-1534438327276-14e5300c3a48",
        split: "photo-1571019613454-1cb2f99b2d8b",
        chapter: "photo-1540497077202-7c8a3999166f",
        features: %w[photo-1549060279-7e168fcee0c2 photo-1576678927484-cc907957088c photo-1544367567-0f2fcb009e0b],
        cards: %w[photo-1571019613454-1cb2f99b2d8b photo-1506126613408-eca07ce68773 photo-1534438327276-14e5300c3a48],
        bento_hero: "photo-1540497077202-7c8a3999166f",
        bento_wide: "photo-1549060279-7e168fcee0c2",
        bento_units: %w[photo-1576678927484-cc907957088c photo-1544367567-0f2fcb009e0b],
        portraits: %w[photo-1539571696357-5a69c17a67c6 photo-1524504388940-b1c1722653e1 photo-1488426862026-3ee34a7d66df photo-1506794778202-cad84cf45f1d]
      },
      "voltage" => {
        hero: "photo-1593941707882-a5bba14938c7",
        split: "photo-1560958089-b8a1929cea89",
        chapter: "photo-1620891549027-942fdc95d3f5",
        features: %w[photo-1449965408869-eaa3f722e40d photo-1536700503339-1e4b06520771 photo-1554744512-d6c603f27c54],
        cards: %w[photo-1617788138017-80ad40651399 photo-1508514177221-188b1cf16e9d photo-1466611653911-95081537e5b7],
        bento_hero: "photo-1536700503339-1e4b06520771",
        bento_wide: "photo-1606016159991-dfe4f2746ad5",
        bento_units: %w[photo-1485291571150-772bcfc10da5 photo-1593941707882-a5bba14938c7],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7 photo-1580489944761-15a19d654956 photo-1472099645785-5658abf4ff4e],
        tiles: %w[photo-1560958089-b8a1929cea89 photo-1620891549027-942fdc95d3f5 photo-1617788138017-80ad40651399
                  photo-1485291571150-772bcfc10da5 photo-1497435334941-8c899ee9e8e9 photo-1536700503339-1e4b06520771],
        places: %w[photo-1612544448445-b8232cff3b6c photo-1616788494707-ec28f08d05a1 photo-1560958089-b8a1929cea89 photo-1536700503339-1e4b06520771]
      },
      "wellspring" => {
        hero: "photo-1538300342682-cf57afb97285",
        split: "photo-1509099836639-18ba1795216d",
        chapter: "photo-1437482078695-73f5ca6c96e2",
        features: %w[photo-1497486751825-1233686d5d80 photo-1542810634-71277d95dcbb photo-1559027615-cd4628902d4a],
        cards: %w[photo-1524069290683-0457abfe42c3 photo-1594708767771-a7502209ff51 photo-1488521787991-ed7bbaae773c],
        bento_hero: "photo-1538300342682-cf57afb97285",
        bento_wide: "photo-1548839140-29a749e1cf4d",
        bento_units: %w[photo-1531206715517-5c0ba140b2b8 photo-1532629345422-7515f3d16bb6],
        portraits: %w[photo-1531123897727-8f129e1688ce photo-1507003211169-0a1dd7228f2d photo-1580489944761-15a19d654956 photo-1506794778202-cad84cf45f1d],
        stories: %w[photo-1497486751825-1233686d5d80 photo-1524069290683-0457abfe42c3 photo-1437482078695-73f5ca6c96e2
                    photo-1542810634-71277d95dcbb photo-1548839140-29a749e1cf4d photo-1509099836639-18ba1795216d]
      },
      "summit" => {
        hero: "photo-1587825140708-dfaf72ae4b04",
        split: "photo-1475721027785-f74eccf877e2",
        chapter: "photo-1531058020387-3be344556be6",
        features: %w[photo-1515187029135-18ee286d815b photo-1591115765373-5207764f72e7 photo-1503428593586-e225b39bddfe],
        cards: %w[photo-1543269865-cbf427effbad photo-1505373877841-8d25f7d46678 photo-1559223607-a43c990c692c],
        bento_hero: "photo-1540575467063-178a50c2df87",
        bento_wide: "photo-1511578314322-379afb476865",
        bento_units: %w[photo-1528605248644-14dd04022da1 photo-1560439514-4e9645039924],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1507003211169-0a1dd7228f2d photo-1534528741775-53994a69daeb photo-1500648767791-00dcc994a43e],
        places: %w[photo-1540575467063-178a50c2df87 photo-1542314831-068cd1dbfeeb photo-1582719478250-c89cae4dc85b]
      },
      "manor" => {
        hero: "photo-1568605114967-8130f3a36994",
        split: "photo-1600585154084-4e5fe7c39198",
        chapter: "photo-1600573472550-8090b5e0745e",
        features: %w[photo-1502005229762-cf1b2da7c5d6 photo-1600585154084-4e5fe7c39198 photo-1600573472550-8090b5e0745e],
        cards: %w[photo-1613490493576-7fde63acd811 photo-1580587771525-78b9dba3b914 photo-1613977257363-707ba9348227],
        bento_hero: "photo-1600596542815-ffad4c1539a9",
        bento_wide: "photo-1512917774080-9991f1c4c750",
        bento_units: %w[photo-1512915922686-57c11dde9b6b photo-1523217582562-09d0def993a6],
        portraits: %w[photo-1573497019940-1c28c88b4f3e photo-1560250097-0b93528c311a photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7],
        listings: %w[photo-1613490493576-7fde63acd811 photo-1600596542815-ffad4c1539a9 photo-1580587771525-78b9dba3b914
                     photo-1512917774080-9991f1c4c750 photo-1613977257363-707ba9348227 photo-1568605114967-8130f3a36994
                     photo-1512915922686-57c11dde9b6b photo-1523217582562-09d0def993a6],
        places: %w[photo-1600585154084-4e5fe7c39198 photo-1600573472550-8090b5e0745e photo-1502005229762-cf1b2da7c5d6]
      },
      "bloom" => {
        hero: "photo-1631214540553-ff044a3ff1d4",
        split: "photo-1522337360788-8b13dee7a37e",
        chapter: "photo-1619451334792-150fd785ee74",
        features: %w[photo-1600428877878-1a0fd85beda8 photo-1503236823255-94609f598e71 photo-1515688594390-b649af70d282],
        cards: %w[photo-1576426863848-c21f53c60b19 photo-1625093742435-6fa192b6fb10 photo-1599305090598-fe179d501227],
        bento_hero: "photo-1631214540553-ff044a3ff1d4",
        bento_wide: "photo-1596755389378-c31d21fd1273",
        bento_units: %w[photo-1573461160327-b450ce3d8e7f photo-1631729371254-42c2892f0e6e],
        portraits: %w[photo-1531123897727-8f129e1688ce photo-1534528741775-53994a69daeb photo-1524504388940-b1c1722653e1 photo-1487412947147-5cebf100ffc2],
        listings: %w[photo-1576426863848-c21f53c60b19 photo-1625093742435-6fa192b6fb10 photo-1599305090598-fe179d501227
                     photo-1620917669809-1af0497965de photo-1617897903246-719242758050 photo-1591360236480-4ed861025fa1
                     photo-1608571423902-eed4a5ad8108 photo-1600428877878-1a0fd85beda8],
        places: %w[photo-1629380321590-3b3f75d66dec photo-1522337360788-8b13dee7a37e photo-1631729371254-42c2892f0e6e]
      },
      "roast" => {
        hero: "photo-1554118811-1e0d58224f24",
        split: "photo-1442512595331-e89e73853f31",
        chapter: "photo-1453614512568-c4024d13c247",
        features: %w[photo-1511920170033-f8396924c348 photo-1497935586351-b67a49e012bf photo-1498804103079-a6351b050096],
        cards: %w[photo-1559056199-641a0ac8b55e photo-1611854779393-1b2da9d400fe photo-1447933601403-0c6688de566e],
        bento_hero: "photo-1509042239860-f550ce710b93",
        bento_wide: "photo-1521017432531-fbd92d768814",
        bento_units: %w[photo-1507133750040-4a8f57021571 photo-1461023058943-07fcbe16d735],
        portraits: %w[photo-1534528741775-53994a69daeb photo-1507003211169-0a1dd7228f2d photo-1524504388940-b1c1722653e1 photo-1500648767791-00dcc994a43e],
        listings: %w[photo-1559056199-641a0ac8b55e photo-1611854779393-1b2da9d400fe photo-1447933601403-0c6688de566e
                     photo-1587734195503-904fca47e0e9 photo-1506372023823-741c83b836fe photo-1461023058943-07fcbe16d735],
        places: %w[photo-1554118811-1e0d58224f24 photo-1521017432531-fbd92d768814 photo-1600093463592-8e36ae95ef56
                   photo-1445116572660-236099ec97a0 photo-1453614512568-c4024d13c247 photo-1501339847302-ac426a4a7cbb]
      },
      "atrium" => {
        hero: "photo-1582555172866-f73bb12a2ab3",
        split: "photo-1545987796-200677ee1011",
        chapter: "photo-1605429523419-d828acb941d9",
        features: %w[photo-1536924940846-227afb31e2a5 photo-1541367777708-7905fe3296c0 photo-1561214115-f2f134cc4912],
        cards: %w[photo-1544967082-d9d25d867d66 photo-1579783902614-a3fb3927b6a5 photo-1552084117-56a987666449],
        bento_hero: "photo-1518998053901-5348d3961a04",
        bento_wide: "photo-1554907984-15263bfd63bd",
        bento_units: %w[photo-1564399579883-451a5d44ec08 photo-1574182245530-967d9b3831af],
        portraits: %w[photo-1544005313-94ddf0286df2 photo-1506794778202-cad84cf45f1d photo-1531123897727-8f129e1688ce photo-1507591064344-4c6ce005b128],
        stories: %w[photo-1545987796-200677ee1011 photo-1536924940846-227afb31e2a5 photo-1579783902614-a3fb3927b6a5
                    photo-1564399579883-451a5d44ec08 photo-1544967082-d9d25d867d66 photo-1541367777708-7905fe3296c0],
        places: %w[photo-1518998053901-5348d3961a04 photo-1554907984-15263bfd63bd photo-1564399579883-451a5d44ec08]
      },
      "canvas" => {
        hero: "photo-1609921212029-bb5a28e60960",
        split: "photo-1559028012-481c04fa702d",
        chapter: "photo-1542744173-8e7e53415bb0",
        features: %w[photo-1454165804606-c3d57bc86b40 photo-1516321318423-f06f85e504b3 photo-1572044162444-ad60f128bdea],
        cards: %w[photo-1559028012-481c04fa702d photo-1600880292089-90a7e086ee0c photo-1558655146-d09347e92766],
        bento_hero: "photo-1609921212029-bb5a28e60960",
        bento_wide: "photo-1522202176988-66273c2fd55f",
        bento_units: %w[photo-1561070791-2526d30994b5 photo-1545239351-1141bd82e8a6],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7 photo-1580489944761-15a19d654956 photo-1472099645785-5658abf4ff4e],
        listings: %w[photo-1558655146-9f40138edfeb photo-1561070791-2526d30994b5 photo-1494438639946-1ebd1d20bf85
                     photo-1541701494587-cb58502866ab photo-1507608616759-54f48f0af0ee photo-1586717791821-3f44a563fa4c
                     photo-1487958449943-2429e8be8625 photo-1545239351-1141bd82e8a6]
      },
      "harbor" => {
        hero: "photo-1441984904996-e0b6ba687e04",
        split: "photo-1472851294608-062f824d29cc",
        chapter: "photo-1604719312566-8912e9227c6a",
        features: %w[photo-1556740758-90de374c12ad photo-1556742111-a301076d9d18 photo-1483985988355-763728e1935b],
        cards: %w[photo-1607083206968-13611e3d76db photo-1556742049-0cfed4f6a45d photo-1441984904996-e0b6ba687e04],
        bento_hero: "photo-1604719312566-8912e9227c6a",
        bento_wide: "photo-1483985988355-763728e1935b",
        bento_units: %w[photo-1556740758-90de374c12ad photo-1556742111-a301076d9d18],
        portraits: %w[photo-1531123897727-8f129e1688ce photo-1506794778202-cad84cf45f1d photo-1544005313-94ddf0286df2 photo-1507591064344-4c6ce005b128],
        listings: %w[photo-1441984904996-e0b6ba687e04 photo-1604719312566-8912e9227c6a photo-1534452203293-494d7ddbf7e0
                     photo-1607083206968-13611e3d76db photo-1528698827591-e19ccd7bc23d photo-1483985988355-763728e1935b
                     photo-1556742111-a301076d9d18 photo-1472851294608-062f824d29cc]
      },
      "spotlight" => {
        hero: "photo-1517336714731-489689fd1ca8",
        split: "photo-1593642632559-0c6d3fc62b89",
        chapter: "photo-1587614382346-4ec70e388b28",
        features: %w[photo-1611186871348-b1ce696e52c9 photo-1525547719571-a2d4ac8945e2 photo-1484788984921-03950022c9ef],
        cards: %w[photo-1498050108023-c5249f4df085 photo-1515378960530-7c0da6231fb1 photo-1603302576837-37561b2e2302],
        bento_hero: "photo-1531297484001-80022131f5a1",
        bento_wide: "photo-1541807084-5c52b6b3adef",
        bento_units: %w[photo-1496181133206-80ce9b88a853 photo-1517694712202-14dd9538aa97],
        portraits: %w[photo-1573496359142-b8d87734a5a2 photo-1519085360753-af0119f7cbe7 photo-1580489944761-15a19d654956 photo-1472099645785-5658abf4ff4e]
      },
      "campaign" => {
        hero: "photo-1552674605-db6ffd4facb5",
        split: "photo-1483721310020-03333e577078",
        chapter: "photo-1486218119243-13883505764c",
        features: %w[photo-1571008887538-b36bb32f4571 photo-1461896836934-ffe607ba8211 photo-1476480862126-209bfaa8edc8],
        cards: %w[photo-1542291026-7eec264c27ff photo-1491553895911-0055eca6402d photo-1556906781-9a412961c28c],
        bento_hero: "photo-1594882645126-14020914d58d",
        bento_wide: "photo-1502904550040-7534597429ae",
        bento_units: %w[photo-1595341888016-a392ef81b7de photo-1552346154-21d32810aba3],
        portraits: %w[photo-1531123897727-8f129e1688ce photo-1506794778202-cad84cf45f1d photo-1544005313-94ddf0286df2 photo-1507591064344-4c6ce005b128],
        listings: %w[photo-1491553895911-0055eca6402d photo-1542291026-7eec264c27ff photo-1476480862126-209bfaa8edc8
                     photo-1571008887538-b36bb32f4571 photo-1483721310020-03333e577078 photo-1556906781-9a412961c28c
                     photo-1460353581641-37baddab0fa2 photo-1486218119243-13883505764c]
      },
      "calm" => {
        hero: "photo-1474418397713-7ede21d49118",
        split: "photo-1545389336-cf090694435e",
        chapter: "photo-1499209974431-9dddcece7f88",
        features: %w[photo-1528715471579-d1bcf0ba5e83 photo-1593811167562-9cef47bfc4d7 photo-1575052814086-f385e2e2ad1b],
        cards: %w[photo-1470252649378-9c29740c9fa8 photo-1544787219-7f47ccb76574 photo-1545389336-cf090694435e],
        bento_hero: "photo-1474418397713-7ede21d49118",
        bento_wide: "photo-1470252649378-9c29740c9fa8",
        bento_units: %w[photo-1593811167562-9cef47bfc4d7 photo-1528715471579-d1bcf0ba5e83],
        portraits: %w[photo-1534528741775-53994a69daeb photo-1524504388940-b1c1722653e1 photo-1488426862026-3ee34a7d66df photo-1544005313-94ddf0286df2],
        listings: %w[photo-1544367567-0f2fcb009e0b photo-1506126613408-eca07ce68773 photo-1515694346937-94d85e41e6f0
                     photo-1528319725582-ddc096101511 photo-1499209974431-9dddcece7f88 photo-1545389336-cf090694435e
                     photo-1575052814086-f385e2e2ad1b photo-1544787219-7f47ccb76574]
      },
      "marque" => {
        hero: "photo-1503376780353-7e6692767b70",
        split: "photo-1542362567-b07e54358753",
        chapter: "photo-1618843479313-40f8afb4b4d8",
        features: %w[photo-1492144534655-ae79c964c9d7 photo-1552519507-da3b142c6e3d photo-1511919884226-fd3cad34687c],
        cards: %w[photo-1489824904134-891ab64532f1 photo-1494976388531-d1058494cdd8 photo-1502877338535-766e1452684a],
        bento_hero: "photo-1544636331-e26879cd4d9b",
        bento_wide: "photo-1617531653332-bd46c24f2068",
        bento_units: %w[photo-1605559424843-9e4c228bf1c2 photo-1555353540-64580b51c258],
        portraits: %w[photo-1560250097-0b93528c311a photo-1519085360753-af0119f7cbe7 photo-1573496359142-b8d87734a5a2 photo-1573497019940-1c28c88b4f3e],
        listings: %w[photo-1560958089-b8a1929cea89 photo-1620891549027-942fdc95d3f5 photo-1617788138017-80ad40651399
                     photo-1485291571150-772bcfc10da5 photo-1503376780353-7e6692767b70 photo-1618843479313-40f8afb4b4d8
                     photo-1544636331-e26879cd4d9b photo-1492144534655-ae79c964c9d7]
      },
      "tempo" => {
        hero: "photo-1470225620780-dba8ba36b745",
        split: "photo-1511379938547-c1f69419868d",
        chapter: "photo-1493225457124-a3eb161ffa5f",
        features: %w[photo-1511671782779-c97d3d27a1d4 photo-1487180144351-b8472da7d491 photo-1514525253161-7a46d19cd819],
        cards: %w[photo-1571330735066-03aaa9429d89 photo-1510915361894-db8b60106cb1 photo-1598488035139-bdbb2231ce04],
        bento_hero: "photo-1524368535928-5b5e00ddc76b",
        bento_wide: "photo-1501612780327-45045538702b",
        bento_units: %w[photo-1429962714451-bb934ecdc4ec photo-1470229722913-7c0e2dbbafd3],
        portraits: %w[photo-1539571696357-5a69c17a67c6 photo-1524504388940-b1c1722653e1 photo-1506794778202-cad84cf45f1d photo-1544005313-94ddf0286df2],
        listings: %w[photo-1470225620780-dba8ba36b745 photo-1511379938547-c1f69419868d photo-1493225457124-a3eb161ffa5f
                     photo-1514525253161-7a46d19cd819 photo-1571330735066-03aaa9429d89 photo-1510915361894-db8b60106cb1
                     photo-1524368535928-5b5e00ddc76b photo-1501612780327-45045538702b]
      },
      "quarterly" => {
        hero: "photo-1481627834876-b7833e8f5570",
        split: "photo-1432821596592-e2c18b78144f",
        chapter: "photo-1456324504439-367cee3b3c32",
        features: %w[photo-1457369804613-52c61a468e7d photo-1473181488821-2d23949a045a photo-1461988320302-91bde64fc8e4],
        cards: %w[photo-1529156069898-49953e39b3ac photo-1513475382585-d06e58bcb0e0 photo-1499750310107-5fef28a66643],
        bento_hero: "photo-1543002588-bfa74002ed7e",
        bento_wide: "photo-1519682337058-a94d519337bc",
        bento_units: %w[photo-1504711434969-e33886168f5c photo-1495020689067-958852a7765e],
        portraits: %w[photo-1544005313-94ddf0286df2 photo-1506794778202-cad84cf45f1d photo-1531123897727-8f129e1688ce photo-1507591064344-4c6ce005b128],
        listings: %w[photo-1494412574643-ff11b0a5c1c3 photo-1504328345606-18bbc8c9d7d1 photo-1495020689067-958852a7765e
                     photo-1507842217343-583bb7270b66 photo-1524995997946-a1c2e315a42f photo-1504711434969-e33886168f5c
                     photo-1481627834876-b7833e8f5570 photo-1456324504439-367cee3b3c32]
      }
    }.freeze
    PALETTE_ALIASES = {
      "article" => "gazette",
      "longform" => "gazette",
      "manifesto" => "cinematic",
      "gallery" => "presence",
      "contact" => "presence",
      "launch" => "lumen",
      "pricing" => "lumen",
      "portfolio" => "folio",
      "menu" => "supper",
      "journal" => "monograph",
      "process" => "clinic",
      "showcase" => "voltage",
      "compare" => "lumen",
      "newsroom" => "gazette",
      "listings" => "manor",
      "stores" => "roast",
      "heritage" => "terrain",
      "conference" => "summit",
      "tour" => "signal",
      "impact" => "ledger",
      "why" => "product"
    }.freeze
    SINGLE_SLOTS = {
      "hero_cinematic" => ["image_url", :hero],
      "hero_split" => ["visual_url", :split],
      "hero_centered" => ["image_url", :bento_wide],
      "split_image_text" => ["image_url", :chapter],
      "product_spotlight" => ["image_url", :bento_wide],
      "image_banner" => ["image_url", :bento_hero],
      "cta_split" => ["image_url", :split]
    }.freeze
    SHOT_FALLBACKS = %i[split chapter bento_wide bento_hero hero cards features listings tiles stories places].freeze
    PHOTO_ID = /photo-[0-9a-zA-Z-]+/

    class << self
      # +used+ collects photo ids already placed on the page so single-image
      # sections fall back to another palette shot instead of repeating one.
      def fill(type, props, palette = nil, used = Set.new)
        set = palette_for(palette)
        hash = stringify(props)
        if (key, slot = single_slot(type, hash))
          fill_key(hash, key, unused_shot(set, slot, used))
        else
          fill_collection(type.to_s, hash, set, used)
        end
        used.merge(hash.to_json.scan(PHOTO_ID))
        hash
      end

      def fill_sections(sections, palette = nil)
        used = Set.new
        Array(sections).map do |section|
          hash = stringify(section)
          type = hash["type"].to_s
          {
            "id" => hash["id"].presence || "sec_#{ULID.generate}",
            "type" => type,
            "props" => fill(type, hash["props"], palette, used)
          }
        end
      end

      def fill_pages(pages, palette = nil)
        Array(pages).map do |page|
          hash = stringify(page)
          hash.merge("sections" => fill_sections(hash["sections"], palette))
        end
      end

      def palette_for(key)
        name = key.to_s.split("_").first
        name = PALETTE_ALIASES[name] || name
        build_palette(name) || default_palette
      end

      def single_slot(type, hash)
        return if type.to_s == "hero_centered" && hash["media_mode"].to_s == "none"

        SINGLE_SLOTS[type.to_s]
      end

      def unused_shot(set, slot, used)
        preferred = set[slot]
        pool = [preferred, *SHOT_FALLBACKS.flat_map { |name| Array(set[name]) }]
        pool.find { |url| !used.include?(photo_id(url)) } || preferred
      end

      def fill_collection(type, hash, set, used)
        case type
        when "card_grid"
          hash["cards"] = fill_list(hash["cards"], "image_url", set[:cards], used)
        when "bento_grid"
          hash["cells"] = fill_bento(hash["cells"], set)
        when "alternating_features"
          hash["items"] = fill_list(hash["items"], "image_url", set[:features], used)
        when "team_grid"
          hash["people"] = fill_list(hash["people"], "image_url", set[:portraits], used)
        when "gallery"
          hash["items"] = fill_list(hash["items"], "image_url", set[:features] + set[:cards], used)
        when "testimonials"
          hash["items"] = fill_list(hash["items"], "image_url", set[:portraits], used)
        when "showcase_tiles"
          hash["tiles"] = fill_list(hash["tiles"], "image_url", set[:tiles], used)
        when "story_index"
          hash["stories"] = fill_list(hash["stories"], "image_url", set[:stories], used)
        when "listing_grid"
          hash["listings"] = fill_list(hash["listings"], "image_url", set[:listings], used)
        when "locations"
          hash["places"] = fill_list(hash["places"], "image_url", set[:places], used)
        when "feature_tabs"
          hash["tabs"] = fill_list(hash["tabs"], "image_url", set[:features], used)
        when "collection_rail"
          hash["items"] = fill_list(hash["items"], "image_url", set[:listings], used)
        end
      end

      def build_palette(name)
        shots = PALETTE_SHOTS[name]
        return if shots.blank?

        with_collections({
          hero: shot(shots[:hero]),
          split: shot(shots[:split]),
          chapter: shot(shots[:chapter]),
          features: shots[:features].map { |id| shot(id) },
          cards: shots[:cards].map { |id| shot(id, width: 1200) },
          bento_hero: shot(shots[:bento_hero]),
          bento_wide: shot(shots[:bento_wide], width: 1400),
          bento_units: shots[:bento_units].map { |id| shot(id, width: 900) },
          portraits: shots[:portraits].map { |id| shot(id, width: 800) }
        }, shots)
      end

      # Collection sections (tiles, listings, places, stories) use a palette's
      # own shot list when it has one, otherwise a mix of its scene shots.
      def with_collections(set, shots = {})
        own = ->(key, width) { shots[key]&.map { |id| shot(id, width: width) } }
        set.merge(
          tiles: own.call(:tiles, 1800) || [set[:hero], set[:chapter], set[:bento_wide], set[:bento_hero], *set[:cards]],
          stories: own.call(:stories, 1400) || [set[:bento_hero], *set[:cards], *set[:features]],
          listings: own.call(:listings, 1000) || [*set[:cards], *set[:features]],
          places: own.call(:places, 1200) || [set[:chapter], set[:bento_wide], set[:split], *set[:features]]
        )
      end

      def stringify(value)
        return {} if value.blank?
        return value.stringify_keys if value.respond_to?(:stringify_keys)

        {}
      end

      def fill_key(hash, key, url)
        current = hash[key].to_s.strip
        if current.blank? || (replaceable?(current) && photo_id(current) != photo_id(url))
          hash[key] = url
        end
        hash
      end

      def photo_id(url)
        url.to_s[PHOTO_ID]
      end

      def replaceable?(url)
        id = photo_id(url)
        id.present? && (STOCK_IDS.include?(id) || DEAD_IDS.include?(id))
      end

      def dead_media?(url)
        id = photo_id(url)
        id.present? && DEAD_IDS.include?(id)
      end

      def fill_list(items, key, urls, used = Set.new)
        list = Array(items)
        fresh, seen = urls.partition { |url| !used.include?(photo_id(url)) }
        urls = fresh + seen if fresh.any?
        list.map.with_index do |item, index|
          fill_key(stringify(item), key, urls[index % urls.length])
        end
      end

      def fill_bento(cells, set)
        unit_index = 0
        units = set[:bento_units]
        Array(cells).map do |cell|
          item = stringify(cell)
          url = case item["span"].to_s
          when "hero" then set[:bento_hero]
          when "wide" then set[:bento_wide]
          else
            chosen = units[unit_index % units.length]
            unit_index += 1
            chosen
          end
          fill_key(item, "image_url", url)
        end
      end

      def default_palette
        with_collections({
          hero: HERO_CINEMATIC,
          split: HERO_SPLIT,
          chapter: SPLIT,
          features: FEATURES,
          cards: CARDS,
          bento_hero: BENTO_HERO,
          bento_wide: BENTO_WIDE,
          bento_units: BENTO_UNITS,
          portraits: PORTRAITS
        })
      end
    end
  end
end
