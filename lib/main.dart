import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:xml/xml.dart' show XmlDocument, XmlElement, parse;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeago/timeago.dart';
import 'dart:developer';

// After installing the package for xml, I needed to restart
// Android Studio to resolve an error about the package URI not existing
// ??

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      title: 'Flutter Demo: BoardGameGeek Hot List',
      theme: new ThemeData(
        primarySwatch: Colors.deepOrange,
      ),
      home: new MyHomePage(title: 'BoardGameGeek.com Hot List'),
    );
  }
}

const NEXT_CACHE_UPDATE_EPOCH_KEY = 'HOT_CACHE_NEXT_UPDATE';

class MyHomePage extends StatefulWidget {
  MyHomePage({Key key, this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => new _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<BoardGameItem> _hotGames = new List(0);
  DateTime _lastUpdate;
  DateTime _nextUpdate;


  static Future<SharedPreferences> _getSharedPreferences() async =>
      await SharedPreferences.getInstance();

  static _getDefaultHotGameInfo() {
    var body = '''
<?xml version="1.0" encoding="utf-8"?>
<items termsofuse="https://boardgamegeek.com/xmlapi/termsofuse">
</items>      
      ''';
    return parse(body);
  }

  @override
  void initState() {
    super.initState();
    initStateAsync();
  }

  initStateAsync() async {
    var hotGames = await _getHotGameInfo();
    setState(() {
      _hotGames = _buildHotGamesList(hotGames);
    });
  }

  Future<File> _getCacheFile() async {
    final dir = (await getApplicationDocumentsDirectory()).path;
    return new File('$dir/hotlist.xml');
  }

  Future<XmlDocument> _getHotListCache() async {
    try {
      final file = await _getCacheFile();
      return parse(await file.readAsString());
    }
    on FileSystemException {
      return _getDefaultHotGameInfo();
    }
  }

  Future<bool> _hotListCacheFileExists() async =>
      await (await _getCacheFile()).exists();


  Future<Null> _saveHotListToCache(XmlDocument doc) async {
    try {
      final file = await _getCacheFile();
      final sink = await file.openWrite();
      await sink.write(doc.toXmlString(pretty: true));
      await sink.close();
      final prefs = await SharedPreferences.getInstance();
      final later = new DateTime.now().add(new Duration(hours: 8));
      prefs.setInt(NEXT_CACHE_UPDATE_EPOCH_KEY, later.millisecondsSinceEpoch);
      setState(() {
        _nextUpdate = new DateTime.fromMicrosecondsSinceEpoch(
            later.millisecondsSinceEpoch * 1000);
        _lastUpdate = new DateTime.now();
      });
      await prefs.commit();
    }
    catch (exception) {
      debugPrint(exception);
    }
  }


  Future<int> _getUpdateTimeStamp() async =>
      (await _getSharedPreferences()).getInt(NEXT_CACHE_UPDATE_EPOCH_KEY) ?? 0;

  Future<bool> _isCacheStale() async {
    final now = new DateTime.now().millisecondsSinceEpoch;
    //return now > updateNeededAfterTime;
    return true;
  }

  Future<XmlDocument> _getHotGameInfo({bool override = false}) async {
    if (await _isCacheStale()) {
      return await _updateHotGameList();
    }

    // cache isn't stale, but ...
    if (await _hotListCacheFileExists()) {
      return await _getHotListCache();
    }

    return await _updateHotGameList();
  }

  Future<XmlDocument> _updateHotGameList() async {
    const url = 'https://www.boardgamegeek.com/xmlapi2/hot?type=boardgame';
    final httpClient = new HttpClient();

    XmlDocument result;
    try {
      final request = await httpClient.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode == HttpStatus.OK) {
        final body = await response.transform(UTF8.decoder).join();
        result = parse(body);
        await _saveHotListToCache(result);
      }
    } catch (exception) {
      result = _getDefaultHotGameInfo();
    }

    return result;
  }

  _buildHotGamesList(XmlDocument hotGames) {
    final items = hotGames.findAllElements('item');
    return new List.from(
        items.map<BoardGameItem>((item) => new BoardGameItem.fromXml(item)));
  }

  _selectGameItem(BuildContext context, BoardGameItem item) {
    print('Tap ${item.name}');
    _showGameItem(context, item);
  }

  _showGameItem(BuildContext context, BoardGameItem item) {
    Navigator.push(context, new MaterialPageRoute(
        builder: (BuildContext context) {
          return new Scaffold(
              appBar: new AppBar(
                  title: new Text(item.name)
              ),
              body: new SizedBox.expand(
                  child: new Hero(tag: item.id,
                      child: new Container(
                          child: new Column(
                            children: <Widget>[
                              new Container(
                                  child: new ConstrainedBox(
                                      constraints: const BoxConstraints(
                                          maxHeight: 250.0, maxWidth: 250.0),
                                      child: new Image.network(
                                          item.thumbnailUrl, width: 250.0,
                                          fit: BoxFit.scaleDown)
                                  )
                              )
                            ],
                          )
                      )
                  )
              )
          );
        }
    ));
  }

  _buildHotGameItem(BuildContext context, int index) {
    final themeData = Theme.of(context);
    final item = _hotGames[index];
    return new GestureDetector(
        onTap: () {
          _selectGameItem(context, item);
        },
        child: new Container(
            margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
            child:
            new Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                new Container(
                  margin: const EdgeInsets.only(right: 16.0),
                  child: new ConstrainedBox(
                      constraints: const BoxConstraints(
                          maxHeight: 100.0, maxWidth: 100.0),
                      child: new Image.network(
                          item.thumbnailUrl, width: 100.0,
                          fit: BoxFit.scaleDown)
                  ),
                ),
                // without Expanded here, the Column will fill infinitely
                // horizontally
                new Expanded(

                    child:
                    new Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        new Text(item.name, style: themeData
                            .textTheme
                            .title, softWrap: true)
                        ,
                        new Text(item.yearPublished, style: themeData
                            .textTheme
                            .subhead),
                      ],
                    )
                ),
              ]
              ,
            )
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    final lv = new ListView.builder(
        itemBuilder: _buildHotGameItem, itemCount: _hotGames.length);
    final nextUpdate = _nextUpdate != null
        ? new TimeAgo().format(_nextUpdate, until: true)
        : "Unknown Games";
    return new Scaffold(
      appBar: new AppBar(
        title: new Text(widget.title),
      ),
      body:
      new Column(
        children: <Widget>[
          new Expanded(child: lv),
          new Divider(height: 1.0),
          new Row(
              mainAxisSize: MainAxisSize.max,
              children: <Widget>[
                new Expanded(
                    child:
                    new Container(
                        padding: const EdgeInsets.all(6.0),
                        decoration: new BoxDecoration(color: Theme
                            .of(context)
                            .highlightColor),
                        child:
                        new Text('Next update: ${nextUpdate}', style:
                        new TextStyle(
                            fontWeight: FontWeight.bold
                        )
                        )
                    )
                )
              ]

          )
        ],
        verticalDirection: VerticalDirection.down,
      )
      ,
      floatingActionButton: new FloatingActionButton(
        onPressed: _getHotGameInfo,
        tooltip: 'Refresh',
        child: new Icon(Icons.refresh),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}


class BoardGameItem {
  String id;
  int rank;
  String thumbnailUrl;
  String name;
  String yearPublished;

  BoardGameItem(this.id, this.name, this.yearPublished, this.thumbnailUrl,
      String rank) {
    this.rank = int.parse(rank);
  }

  BoardGameItem.fromXml(XmlElement item)
  {
    id = item.getAttribute('id');
    rank = int.parse(item.getAttribute('rank'));
    name = _getNamedElementValue(item, 'name');
    thumbnailUrl = _getNamedElementValue(item, 'thumbnail');
    yearPublished = _getNamedElementValue(item, 'yearpublished');
  }

  static String _getNamedElementValue(XmlElement ele, String name) {
    final all = ele.findAllElements(name);
    if (all.length == 0) {
      return "";
    }
    return all.first.getAttribute('value');
  }
}