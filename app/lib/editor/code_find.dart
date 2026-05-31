/// code_find.dart — Search and replace API for the code editor.
///
/// Provides [CodeFindController] (search state and navigation),
/// [CodeFindValue] (immutable search state snapshot), [CodeFindOption]
/// (search flags: pattern, case-sensitivity, regex), and [CodeFindResult]
/// (matched selections with current index).

part of editor;

/// Signature for a builder that creates the search/replace overlay widget.
typedef CodeFindBuilder = PreferredSizeWidget Function(BuildContext context, CodeFindController controller, bool readonly);

/// Immutable snapshot of the current search/replace state.
///
/// Holds the active [option], whether replace mode is enabled, the latest
/// [result] (if any), and a [searching] flag that is true while an
/// asynchronous search is in progress.
class CodeFindValue {

  final CodeFindOption option;
  final bool replaceMode;
  final CodeFindResult? result;
  final bool searching;

  const CodeFindValue({
    required this.option,
    required this.replaceMode,
    this.result,
    this.searching = false,
  });

  const CodeFindValue.empty() : this(
    option: const CodeFindOption(
      pattern: '',
      caseSensitive: false,
      regex: false,
    ),
    replaceMode: false,
  );

  CodeFindValue copyWith({
    CodeFindOption? option,
    bool? replaceMode,
    required CodeFindResult? result,
    bool? searching,
  }) {
    return CodeFindValue(
      option: option ?? this.option,
      replaceMode: replaceMode ?? this.replaceMode,
      result: result,
      searching: searching ?? this.searching,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFindValue
        && other.option == option
        && other.replaceMode == replaceMode
        && other.result == result
        && other.searching == searching;
  }

  @override
  int get hashCode => Object.hash(option, replaceMode, result, searching);

  @override
  String toString() {
    return '{option: $option replaceMode: $replaceMode result: $result searching:$searching}';
  }

}

/// Search flags that control how the pattern is matched.
///
/// Combines the raw [pattern] string with [caseSensitive] and [regex] toggles.
/// Use [regExp] to obtain the compiled [RegExp] (returns null if the regex
/// syntax is invalid).
class CodeFindOption {

  /// The raw search pattern entered by the user.
  final String pattern;

  /// Whether the search should be case-sensitive.
  final bool caseSensitive;

  /// Whether [pattern] should be interpreted as a regular expression.
  final bool regex;

  const CodeFindOption({
    required this.pattern,
    required this.caseSensitive,
    required this.regex,
  });

  CodeFindOption copyWith({
    String? pattern,
    bool? caseSensitive,
    bool? regex,
  }) {
    return CodeFindOption(
      pattern: pattern ?? this.pattern,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      regex: regex ?? this.regex,
    );
  }

  RegExp? get regExp {
    if (regex) {
      try {
        return RegExp(pattern, caseSensitive: caseSensitive);
      } on FormatException {
        return null;
      }
    } else {
      return RegExp(RegExp.escape(pattern), caseSensitive: caseSensitive);
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFindOption
        && other.pattern == pattern
        && other.caseSensitive == caseSensitive
        && other.regex == regex;
  }

  @override
  int get hashCode => Object.hash(pattern, caseSensitive, regex);

  @override
  String toString() {
    return '{pattern: $pattern caseSensitive: $caseSensitive regex: $regex}';
  }

}

/// The result of a search operation.
///
/// Contains all [matches] found in [codeLines] for the given [option],
/// plus a cursor [index] pointing to the currently highlighted match.
/// The [dirty] flag indicates the result may be stale because the
/// underlying code has changed since the search ran.
class CodeFindResult {

  /// Zero-based index of the currently highlighted match, or -1 if none.
  final int index;

  /// All matched selections in document order.
  final List<CodeLineSelection> matches;

  /// The search option that produced this result.
  final CodeFindOption option;

  /// Snapshot of the code lines at the time the search was executed.
  final CodeLines codeLines;

  /// Whether the code has been modified since this result was computed.
  final bool dirty;

  const CodeFindResult({
    required this.index,
    required this.matches,
    required this.option,
    required this.codeLines,
    required this.dirty,
  });

  CodeFindResult get previous => copyWith(
    index: index == 0 ? matches.length - 1 : index - 1
  );

  CodeFindResult get next => copyWith(
    index: index == matches.length - 1 ? 0 : index + 1
  );

  CodeLineSelection? get currentMatch => index == -1 ? null : matches[index];

  CodeFindResult copyWith({
    int? index,
    List<CodeLineSelection>? matches,
    CodeFindOption? option,
    CodeLines? codeLines,
    bool? dirty,
  }) {
    return CodeFindResult(
      index: index ?? this.index,
      matches: matches ?? this.matches,
      option: option ?? this.option,
      codeLines: codeLines ?? this.codeLines,
      dirty: dirty ?? this.dirty,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is CodeFindResult
        && other.index == index
        && listEquals(other.matches, matches)
        && other.option == option
        && other.codeLines.equals(codeLines)
        && other.dirty == dirty;
  }

  @override
  int get hashCode => Object.hash(index, matches, option, codeLines, dirty);

}

/// Controller for the search/replace feature of the code editor.
///
/// Manages search state, match navigation, and replacement operations.
/// Wraps a [ValueNotifier] whose value is the current [CodeFindValue]
/// (null when the search panel is closed).
///
/// Pass an instance to [CodeEditor.findController] to share search state,
/// or let the editor create one internally.
abstract class CodeFindController extends ValueNotifier<CodeFindValue?> {

  /// Creates a find controller bound to the given editing [controller].
  factory CodeFindController(CodeLineEditingController controller, [CodeFindValue? value])
    => _CodeFindControllerImpl(controller, value);

  /// Text controller for the search input field.
  TextEditingController get findInputController;

  /// Text controller for the replace input field.
  TextEditingController get replaceInputController;

  /// Focus node for the search input field.
  FocusNode get findInputFocusNode;

  /// Focus node for the replace input field.
  FocusNode get replaceInputFocusNode;

  /// All matched selections in the current search result, or null if idle.
  List<CodeLineSelection>? get allMatchSelections;

  /// The currently highlighted match selection, or null if none.
  CodeLineSelection? get currentMatchSelection;

  /// Open the search panel in find-only mode.
  void findMode();

  /// Open the search panel in find-and-replace mode.
  void replaceMode();

  /// Move keyboard focus to the search input field.
  void focusOnFindInput();

  /// Move keyboard focus to the replace input field.
  void focusOnReplaceInput();

  /// Toggle between find-only and find-and-replace modes.
  void toggleMode();

  /// Close the search panel and clear the search state.
  void close();

  /// Toggle the regex search flag.
  void toggleRegex();

  /// Toggle the case-sensitive search flag.
  void toggleCaseSensitive();

  /// Navigate to the previous match in the result list.
  void previousMatch();

  /// Navigate to the next match in the result list.
  void nextMatch();

  /// Replace the currently highlighted match with the replace input text.
  void replaceMatch();

  /// Replace all matches with the replace input text.
  void replaceAllMatches();

  /// Convert a match selection to the actual document selection,
  /// accounting for folded chunks. Returns null if the match is hidden.
  CodeLineSelection? convertMatchToSelection(CodeLineSelection match);

}