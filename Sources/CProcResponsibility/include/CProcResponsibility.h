#ifndef C_PROC_RESPONSIBILITY_H
#define C_PROC_RESPONSIBILITY_H

#include <sys/types.h>

/*
 * ADR-8 / Should-1: あるプロセス（例: ブラウザのレンダラー）が「責任を持つプロセス」
 * （= 本体プロセス。Chrome レンダラーなら Chrome 本体）の PID を返す薄い C シム。
 *
 * libSystem の private シンボル `responsibility_get_pid_responsible_for_pid(pid_t)` を
 * ラップする。NSRunningApplication に非登録（bundleId=nil）なレンダラーを、対象アプリの
 * メイン PID に「責任を持つプロセス」として捕捉するために使う（非混入: 責任元が対象アプリの
 * プロセスのみ採用）。
 *
 * 返り値:
 *  - 成功時: 引数プロセスに責任を持つプロセスの PID（自分自身が責任元なら自 PID）。
 *  - 取得不能/エラー: 負値（< 0）。呼び出し側（Swift）はこれを nil に倒す。
 *
 * 注: 集約判定（責任元が対象メイン PID か）の本質的なロジックは Swift 側の ProcessMatcher
 *     （純粋関数・OS 非接触・ユニットテスト対象）に置く。本シムは値の取得のみを担う。
 */
pid_t stc_responsible_pid_for_pid(pid_t pid);

#endif /* C_PROC_RESPONSIBILITY_H */
