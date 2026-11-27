import 'package:hugeicons/hugeicons.dart';
import 'package:material_ui/material_ui.dart';

/// An icon from the Hugeicons stroke-rounded set.
typedef AppIconData = List<List<dynamic>>;

/// Every icon the app uses, named for what it means here, so one set is
/// used everywhere and a swap happens in one place.
abstract final class AppIcons {
  static const add = HugeIcons.strokeRoundedAdd01;
  static const search = HugeIcons.strokeRoundedSearch01;
  static const noResults = HugeIcons.strokeRoundedSearchRemove;
  static const recurring = HugeIcons.strokeRoundedCalendarSync;
  static const next = HugeIcons.strokeRoundedArrowRight01;
  static const previous = HugeIcons.strokeRoundedArrowLeft01;
  static const back = HugeIcons.strokeRoundedArrowLeft02;
  static const dropDown = HugeIcons.strokeRoundedArrowDown01;
  static const notification = HugeIcons.strokeRoundedNotification01;
  static const capture = HugeIcons.strokeRoundedNotification03;
  static const notificationOff = HugeIcons.strokeRoundedNotificationOff01;
  static const notificationPaused = HugeIcons.strokeRoundedNotificationSnooze01;
  static const note = HugeIcons.strokeRoundedNoteEdit;
  static const edit = HugeIcons.strokeRoundedPencilEdit02;
  static const calendar = HugeIcons.strokeRoundedCalendar03;
  static const calendarDay = HugeIcons.strokeRoundedCalendar01;
  static const calendarFree = HugeIcons.strokeRoundedCalendarCheckIn01;
  static const calendarEnd = HugeIcons.strokeRoundedCalendarRemove01;
  static const time = HugeIcons.strokeRoundedClock01;
  static const filter = HugeIcons.strokeRoundedFilterHorizontal;
  static const compare = HugeIcons.strokeRoundedArrowDataTransferHorizontal;
  static const stats = HugeIcons.strokeRoundedPieChart;
  static const transactions = HugeIcons.strokeRoundedReceiptIndianRupee;
  static const screenshot = HugeIcons.strokeRoundedImage02;
  static const wallet = HugeIcons.strokeRoundedWallet01;
  static const more = HugeIcons.strokeRoundedMoreHorizontal;
  static const check = HugeIcons.strokeRoundedTick02;
  static const done = HugeIcons.strokeRoundedCheckmarkCircle02;
  static const inbox = HugeIcons.strokeRoundedInbox;
  static const categories = HugeIcons.strokeRoundedDashboardSquare02;
  static const budget = HugeIcons.strokeRoundedPiggyBank;
  static const importFile = HugeIcons.strokeRoundedFileImport;
  static const exportFile = HugeIcons.strokeRoundedFileExport;
  static const backup = HugeIcons.strokeRoundedCloudUpload;
  static const restore = HugeIcons.strokeRoundedCloudDownload;
  static const ai = HugeIcons.strokeRoundedAiMagic;
  static const privacy = HugeIcons.strokeRoundedSquareLock01;
  static const delete = HugeIcons.strokeRoundedDelete02;
  static const close = HugeIcons.strokeRoundedCancel01;
  static const repeat = HugeIcons.strokeRoundedRepeat;
  static const paused = HugeIcons.strokeRoundedPauseCircle;
  static const stop = HugeIcons.strokeRoundedStop;
  static const mic = HugeIcons.strokeRoundedMic01;
  static const voice = HugeIcons.strokeRoundedVoice;
  static const enter = HugeIcons.strokeRoundedArrowTurnBackward;
  static const scan = HugeIcons.strokeRoundedScan;
  static const warning = HugeIcons.strokeRoundedAlert02;
  static const person = HugeIcons.strokeRoundedUser;
  static const tag = HugeIcons.strokeRoundedHashtag;
  static const brokenImage = HugeIcons.strokeRoundedImageNotFound01;
  static const phone = HugeIcons.strokeRoundedSmartPhone01;
  static const info = HugeIcons.strokeRoundedInformationCircle;
  static const table = HugeIcons.strokeRoundedTable;
  static const share = HugeIcons.strokeRoundedShare08;
  static const columns = HugeIcons.strokeRoundedLayout3Column;
  static const copy = HugeIcons.strokeRoundedCopy01;
  static const upload = HugeIcons.strokeRoundedFileUpload;
  static const history = HugeIcons.strokeRoundedTransactionHistory;
  static const cash = HugeIcons.strokeRoundedMoney03;
  static const bank = HugeIcons.strokeRoundedBank;
  static const creditCard = HugeIcons.strokeRoundedCreditCard;
  static const lent = HugeIcons.strokeRoundedAgreement02;
  static const lock = HugeIcons.strokeRoundedSquareLock02;
  static const fingerprint = HugeIcons.strokeRoundedFingerPrint;
  static const autoBackup = HugeIcons.strokeRoundedDatabaseSync01;
  static const folder = HugeIcons.strokeRoundedFolder01;
  static const goal = HugeIcons.strokeRoundedTarget02;
  static const putIn = HugeIcons.strokeRoundedMoneyAdd02;
  static const takeOut = HugeIcons.strokeRoundedMoneyRemove02;
  static const archive = HugeIcons.strokeRoundedArchive02;
  static const insights = HugeIcons.strokeRoundedIdea01;
  static const up = HugeIcons.strokeRoundedArrowUpRight01;
  static const down = HugeIcons.strokeRoundedArrowDownRight01;
}

/// Draws an [AppIcons] icon. Size and colour follow the surrounding icon
/// theme when not given, like Flutter's own Icon, so buttons, list tiles and
/// the navigation bar style it the same way.
class AppIcon extends StatelessWidget {
  const AppIcon(this.icon, {super.key, this.size, this.color, this.strokeWidth});

  final AppIconData icon;
  final double? size;
  final Color? color;

  /// Line weight. Hugeicons are drawn at 1.5 unless this is set.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final dimension = size ?? IconTheme.of(context).size ?? 24;
    // Like Icon, keep the drawing at its own size and centre it when a
    // parent forces a bigger box, as text field icons and buttons do.
    return SizedBox.square(
      dimension: dimension,
      child: Center(
        child: HugeIcon(icon: icon, size: dimension, color: color, strokeWidth: strokeWidth),
      ),
    );
  }
}
