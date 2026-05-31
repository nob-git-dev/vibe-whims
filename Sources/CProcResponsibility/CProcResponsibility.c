#include "CProcResponsibility.h"

#include <sys/types.h>

/*
 * libSystem に存在する private シンボル。公開ヘッダには宣言が無いため、ここで extern 宣言する。
 * 署名: pid_t responsibility_get_pid_responsible_for_pid(pid_t pid);
 * （responsibility_* は libsystem_coreservices 由来。明示リンク不要で libSystem からシンボル解決される。）
 */
extern pid_t responsibility_get_pid_responsible_for_pid(pid_t pid);

pid_t stc_responsible_pid_for_pid(pid_t pid) {
    if (pid <= 0) {
        return -1; /* 不正入力は取得不能扱い（呼び出し側で nil 化）。 */
    }
    pid_t responsible = responsibility_get_pid_responsible_for_pid(pid);
    if (responsible <= 0) {
        return -1; /* エラー/取得不能（負値・0）は取得不能扱い。 */
    }
    return responsible;
}
