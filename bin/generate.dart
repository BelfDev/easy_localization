// ignore_for_file: omit_local_variable_types, unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as path;

const _preservedKeywords = [
  'few',
  'many',
  'one',
  'other',
  'two',
  'zero',
  'male',
  'female',
];

void main(List<String> args) {
  if (_isHelpCommand(args)) {
    _printHelperDisplay();
  } else {
    handleLangFiles(_generateOption(args));
  }
}

bool _isHelpCommand(List<String> args) {
  return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
}

void _printHelperDisplay() {
  var parser = _generateArgParser(null);
  print(parser.usage);
}

GenerateOptions _generateOption(List<String> args) {
  var generateOptions = GenerateOptions();
  var parser = _generateArgParser(generateOptions);
  parser.parse(args);
  return generateOptions;
}

ArgParser _generateArgParser(GenerateOptions? generateOptions) {
  var parser = ArgParser();

  parser.addOption('source-dir',
      abbr: 'S',
      defaultsTo: 'resources/langs',
      callback: (String? x) => generateOptions!.sourceDir = x,
      help: 'Folder containing localization files');

  parser.addOption('source-file',
      abbr: 's',
      callback: (String? x) => generateOptions!.sourceFile = x,
      help: 'File to use for localization');

  parser.addOption('output-dir',
      abbr: 'O',
      defaultsTo: 'lib/generated',
      callback: (String? x) => generateOptions!.outputDir = x,
      help: 'Output folder stores for the generated file');

  parser.addOption('output-file',
      abbr: 'o',
      defaultsTo: 'codegen_loader.g.dart',
      callback: (String? x) => generateOptions!.outputFile = x,
      help: 'Output file name');

  parser.addOption('format',
      abbr: 'f',
      defaultsTo: 'json',
      callback: (String? x) => generateOptions!.format = x,
      help: 'Support json or keys formats',
      allowed: ['json', 'keys']);

  parser.addFlag(
    'skip-unnecessary-keys',
    abbr: 'u',
    defaultsTo: false,
    callback: (bool? x) => generateOptions!.skipUnnecessaryKeys = x,
    help: 'If true - Skip unnecessary keys of nested objects.',
  );

  return parser;
}

class GenerateOptions {
  String? sourceDir;
  String? sourceFile;
  String? templateLocale;
  String? outputDir;
  String? outputFile;
  String? format;
  bool? skipUnnecessaryKeys;

  @override
  String toString() {
    return 'format: $format sourceDir: $sourceDir sourceFile: $sourceFile outputDir: $outputDir outputFile: $outputFile skipUnnecessaryKeys: $skipUnnecessaryKeys';
  }
}

void handleLangFiles(GenerateOptions options) async {
  final current = Directory.current;
  final source = Directory.fromUri(Uri.parse(options.sourceDir!));
  final output = Directory.fromUri(Uri.parse(options.outputDir!));
  final sourcePath = Directory(path.join(current.path, source.path));
  final outputPath =
      Directory(path.join(current.path, output.path, options.outputFile));

  if (!await sourcePath.exists()) {
    printError('Source path does not exist');
    return;
  }

  var files = await dirContents(sourcePath);
  if (options.sourceFile != null) {
    final sourceFile = File(path.join(source.path, options.sourceFile));
    if (!await sourceFile.exists()) {
      printError('Source file does not exist (${sourceFile.toString()})');
      return;
    }
    files = [sourceFile];
  } else {
    //filtering format
    files = files.where((f) => f.path.contains('.json')).toList();
  }

  if (files.isNotEmpty) {
    generateFile(files, outputPath, options);
  } else {
    printError('Source path empty');
  }
}

Future<List<FileSystemEntity>> dirContents(Directory dir) {
  var files = <FileSystemEntity>[];
  var completer = Completer<List<FileSystemEntity>>();
  var lister = dir.list(recursive: false);
  lister.listen((file) => files.add(file),
      onDone: () => completer.complete(files));
  return completer.future;
}

void generateFile(List<FileSystemEntity> files, Directory outputPath,
    GenerateOptions options) async {
  var generatedFile = File(outputPath.path);
  if (!generatedFile.existsSync()) {
    generatedFile.createSync(recursive: true);
  }

  var classBuilder = StringBuffer();

  switch (options.format) {
    case 'json':
      await _writeJson(classBuilder, files);
      break;
    case 'keys':
      await _writeKeys(
          classBuilder, files, options.skipUnnecessaryKeys, options.outputFile);
      break;
    // case 'csv':
    //   await _writeCsv(classBuilder, files);
    // break;
    default:
      printError('Format not support');
  }

  classBuilder.writeln('}');
  generatedFile.writeAsStringSync(classBuilder.toString());

  printInfo('All done! File generated in ${outputPath.path}');
}

Future _writeKeys(StringBuffer classBuilder, List<FileSystemEntity> files,
    bool? skipUnnecessaryKeys, String? outputFile) async {
  final className = outputFile?.split('.').first.toPascalCase ?? 'LocaleKeys';

  var file = '''
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart

abstract class $className {
''';

  final fileData = File(files.first.path);

  Map<String, dynamic> translations =
      json.decode(await fileData.readAsString());

  file += _resolve(translations, skipUnnecessaryKeys);

  classBuilder.writeln(file);
}

String _resolve(Map<String, dynamic> translations, bool? skipUnnecessaryKeys,
    [String? accKey]) {
  var fileContent = '';

  final sortedKeys = translations.keys.toList();

  final canIgnoreKeys = skipUnnecessaryKeys == true;

  bool containsPreservedKeywords(Map<String, dynamic> map) =>
      map.keys.any((element) => _preservedKeywords.contains(element));

  for (var key in sortedKeys) {
    var ignoreKey = false;
    if (translations[key] is Map) {
      // If key does not contain keys for plural(), gender() etc. and option is enabled -> ignore it
      ignoreKey = !containsPreservedKeywords(
              translations[key] as Map<String, dynamic>) &&
          canIgnoreKeys;

      var nextAccKey = key;
      if (accKey != null) {
        nextAccKey = '$accKey.$key';
      }

      fileContent +=
          _resolve(translations[key], skipUnnecessaryKeys, nextAccKey);
    }

    if (!_preservedKeywords.contains(key)) {
      if (accKey != null && !ignoreKey) {
        final formattedAccKey = '${accKey.toCamelCase}.$key'.toCamelCase;

        fileContent += '  static const $formattedAccKey = \'$accKey.$key\';\n';
      } else if (!ignoreKey) {
        fileContent += '  static const $key = \'$key\';\n';
      }
    }
  }

  return fileContent;
}

Future _writeJson(
    StringBuffer classBuilder, List<FileSystemEntity> files) async {
  var gFile = '''
// DO NOT EDIT. This is code generated via package:easy_localization/generate.dart

// ignore_for_file: prefer_single_quotes

import 'dart:ui';

import 'package:easy_localization/easy_localization.dart' show AssetLoader;

class CodegenLoader extends AssetLoader{
  const CodegenLoader();

  @override
  Future<Map<String, dynamic>> load(String fullPath, Locale locale ) {
    return Future.value(mapLocales[locale.toString()]);
  }

  ''';

  final listLocales = [];

  for (var file in files) {
    final localeName =
        path.basename(file.path).replaceFirst('.json', '').replaceAll('-', '_');
    listLocales.add('"$localeName": $localeName');
    final fileData = File(file.path);

    Map<String, dynamic>? data = json.decode(await fileData.readAsString());

    final mapString = JsonEncoder.withIndent('  ').convert(data);
    gFile += 'static const Map<String,dynamic> $localeName = $mapString;\n';
  }

  gFile +=
      'static const Map<String, Map<String,dynamic>> mapLocales = \{${listLocales.join(', ')}\};';
  classBuilder.writeln(gFile);
}

// _writeCsv(StringBuffer classBuilder, List<FileSystemEntity> files) async {
//   List<String> listLocales = List();
//   final fileData = File(files.first.path);

//   // CSVParser csvParser = CSVParser(await fileData.readAsString());

//   // List listLangs = csvParser.getLanguages();
//   for(String localeName in listLangs){
//     listLocales.add('"$localeName": $localeName');
//     String mapString = JsonEncoder.withIndent("  ").convert(csvParser.getLanguageMap(localeName)) ;

//     classBuilder.writeln(
//       '  static const Map<String,dynamic> $localeName = ${mapString};\n');
//   }

//   classBuilder.writeln(
//       '  static const Map<String, Map<String,dynamic>> mapLocales = \{${listLocales.join(', ')}\};');

// }

void printInfo(String info) {
  print('\u001b[32measy localization: $info\u001b[0m');
}

void printError(String error) {
  print('\u001b[31m[ERROR] easy localization: $error\u001b[0m');
}

// Adapted from https://github.com/techniboogie-dart/recase/blob/master/lib/recase.dart

/// An instance of text to be re-cased.
class _ReCase {
  _ReCase(String text) {
    originalText = text;
    _words = _groupIntoWords(text);
  }

  final RegExp _upperAlphaRegex = RegExp(r'[A-Z]');

  final symbolSet = {' ', '.', '/', '_', r'\', '-'};

  late String originalText;
  late List<String> _words;

  List<String> _groupIntoWords(String text) {
    final StringBuffer sb = StringBuffer();
    final List<String> words = [];
    final bool isAllCaps = text.toUpperCase() == text;

    for (int i = 0; i < text.length; i++) {
      final String char = text[i];
      final String? nextChar = i + 1 == text.length ? null : text[i + 1];

      if (symbolSet.contains(char)) {
        continue;
      }

      sb.write(char);

      final bool isEndOfWord = nextChar == null ||
          (_upperAlphaRegex.hasMatch(nextChar) && !isAllCaps) ||
          symbolSet.contains(nextChar);

      if (isEndOfWord) {
        words.add(sb.toString());
        sb.clear();
      }
    }

    return words;
  }

  /// camelCase
  String get camelCase => _getCamelCase();

  /// CONSTANT_CASE
  String get constantCase => _getConstantCase();

  /// Sentence case
  String get sentenceCase => _getSentenceCase();

  /// snake_case
  String get snakeCase => _getSnakeCase();

  /// dot.case
  String get dotCase => _getSnakeCase(separator: '.');

  /// param-case
  String get paramCase => _getSnakeCase(separator: '-');

  /// path/case
  String get pathCase => _getSnakeCase(separator: '/');

  /// PascalCase
  String get pascalCase => _getPascalCase();

  /// Header-Case
  String get headerCase => _getPascalCase(separator: '-');

  /// Title Case
  String get titleCase => _getPascalCase(separator: ' ');

  String _getCamelCase({String separator = ''}) {
    final List<String> words = _words.map(_upperCaseFirstLetter).toList();
    if (_words.isNotEmpty) {
      words[0] = words[0].toLowerCase();
    }

    return words.join(separator);
  }

  String _getConstantCase({String separator = '_'}) {
    final List<String> words =
        _words.map((word) => word.toUpperCase()).toList();

    return words.join(separator);
  }

  String _getPascalCase({String separator = ''}) {
    final List<String> words = _words.map(_upperCaseFirstLetter).toList();

    return words.join(separator);
  }

  String _getSentenceCase({String separator = ' '}) {
    final List<String> words =
        _words.map((word) => word.toLowerCase()).toList();
    if (_words.isNotEmpty) {
      words[0] = _upperCaseFirstLetter(words[0]);
    }

    return words.join(separator);
  }

  String _getSnakeCase({String separator = '_'}) {
    final List<String> words =
        _words.map((word) => word.toLowerCase()).toList();

    return words.join(separator);
  }

  String _upperCaseFirstLetter(String word) {
    return '${word.substring(0, 1).toUpperCase()}${word.substring(1).toLowerCase()}';
  }
}

extension _StringReCase on String {
  String get toCamelCase => _ReCase(this).camelCase;

  String get toConstantCase => _ReCase(this).constantCase;

  String get toSentenceCase => _ReCase(this).sentenceCase;

  String get toSnakeCase => _ReCase(this).snakeCase;

  String get toDotCase => _ReCase(this).dotCase;

  String get toParamCase => _ReCase(this).paramCase;

  String get toPathCase => _ReCase(this).pathCase;

  String get toPascalCase => _ReCase(this).pascalCase;

  String get toHeaderCase => _ReCase(this).headerCase;

  String get toTitleCase => _ReCase(this).titleCase;
}
