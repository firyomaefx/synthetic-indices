/* BREAK100 offline policy trainer. Console Windows exe. No broker calls. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

#define MAX_N 4000
#define ARMS 4
#define MIN_N 16

typedef struct {
    int side;
    char label[40];
    double mfe, mae, hw;
    int arm;
} Sample;

static const char *ARM_ID[ARMS] = {"balanced", "tight", "wide", "runner"};
static const double ARM_SL[ARMS] = {1.00, 0.85, 1.35, 1.10};
static const double ARM_T1[ARMS] = {1.00, 0.80, 1.20, 1.60};
static const double ARM_T2[ARMS] = {2.00, 1.50, 2.40, 3.00};
static const double ARM_T3[ARMS] = {3.00, 2.20, 4.00, 5.00};

static double clampd(double x, double lo, double hi) {
    if (x < lo) return lo;
    if (x > hi) return hi;
    return x;
}

static double realized_r(const Sample *s, double sl_r, double tp3_r) {
    double hw = s->hw > 1e-9 ? s->hw : 1e-9;
    double stop = sl_r * hw;
    double tp3 = tp3_r * hw;
    double cost = 0.12;
    if (fabs(s->mae) >= stop) return -1.0 - cost;
    double captured = s->mfe > 0.0 ? s->mfe : 0.0;
    if (captured > tp3) captured = tp3;
    return captured / stop - cost;
}

static int parse_csv(const char *path, Sample *out, int cap) {
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    char line[512];
    int n = 0;
    if (!fgets(line, sizeof line, f)) {
        fclose(f);
        return 0;
    }
    while (n < cap && fgets(line, sizeof line, f)) {
        Sample s;
        memset(&s, 0, sizeof s);
        char lab[40];
        lab[0] = 0;
        if (sscanf(line, "%d,%39[^,],%lf,%lf,%lf,%d", &s.side, lab, &s.mfe, &s.mae, &s.hw, &s.arm) < 5)
            continue;
        strncpy(s.label, lab, sizeof s.label - 1);
        if (s.arm < 0 || s.arm >= ARMS) s.arm = 0;
        if (s.hw <= 0.0) continue;
        out[n++] = s;
    }
    fclose(f);
    return n;
}

static void quantile(double *v, int n, double q, double *out) {
    if (n <= 0) {
        *out = 0;
        return;
    }
    for (int i = 0; i < n; i++)
        for (int j = i + 1; j < n; j++)
            if (v[j] < v[i]) {
                double t = v[i];
                v[i] = v[j];
                v[j] = t;
            }
    int idx = (int)floor(q * (n - 1));
    if (idx < 0) idx = 0;
    if (idx > n - 1) idx = n - 1;
    *out = v[idx];
}

static int pick_ucb(const Sample *s, int n) {
    int counts[ARMS] = {0};
    double sums[ARMS] = {0};
    int used = 0;
    for (int i = 0; i < n; i++) {
        int a = s[i].arm;
        if (a < 0 || a >= ARMS) continue;
        counts[a]++;
        sums[a] += realized_r(&s[i], ARM_SL[a], ARM_T3[a]);
        used++;
    }
    if (used < MIN_N) return 0;
    double logn = log(used + 1.0);
    int best = 0;
    double best_sc = -1e100;
    for (int a = 0; a < ARMS; a++) {
        if (counts[a] == 0) return a;
        double mean = sums[a] / counts[a];
        double sc = mean + 1.15 * sqrt(logn / counts[a]);
        if (sc > best_sc) {
            best_sc = sc;
            best = a;
        }
    }
    return best;
}

static int reinforce(const Sample *s, int n) {
    double w[ARMS] = {0, 0, 0, 0};
    const double lr = 0.08;
    for (int ep = 0; ep < 16; ep++) {
        for (int i = 0; i < n; i++) {
            double m = w[0], ex[ARMS], z = 0;
            for (int a = 1; a < ARMS; a++)
                if (w[a] > m) m = w[a];
            for (int a = 0; a < ARMS; a++) {
                ex[a] = exp(w[a] - m);
                z += ex[a];
            }
            int pick = 0;
            double u = (double)((i * 17 + ep * 31) % 1000) / 1000.0;
            double acc = 0;
            for (int a = 0; a < ARMS; a++) {
                acc += ex[a] / z;
                if (u <= acc) {
                    pick = a;
                    break;
                }
            }
            double r = realized_r(&s[i], ARM_SL[pick], ARM_T3[pick]);
            for (int a = 0; a < ARMS; a++) {
                double p = ex[a] / z;
                w[a] += lr * ((a == pick ? 1.0 : 0.0) - p) * r;
            }
        }
    }
    int best = 0;
    for (int a = 1; a < ARMS; a++)
        if (w[a] > w[best]) best = a;
    return best;
}

typedef struct {
    int ready, n, arm;
    char source[24];
    double sl, t1, t2, t3, mean_r, oos_r;
} Policy;

static void blend(const Sample *s, int n, int arm, Policy *p) {
    double mae[MAX_N], mfe[MAX_N];
    int nm = 0, nf = 0;
    for (int i = 0; i < n; i++) {
        double hw = s[i].hw > 1e-9 ? s[i].hw : 1e-9;
        mae[nm++] = fabs(s[i].mae) / hw;
        if (strstr(s[i].label, "BREAKOUT"))
            mfe[nf++] = (s[i].mfe > 0 ? s[i].mfe : 0) / hw;
    }
    double qsl = ARM_SL[arm], q1 = ARM_T1[arm], q2 = ARM_T2[arm], q3 = ARM_T3[arm];
    if (nm) quantile(mae, nm, 0.75, &qsl);
    if (nf) {
        quantile(mfe, nf, 0.40, &q1);
        quantile(mfe, nf, 0.65, &q2);
        quantile(mfe, nf, 0.85, &q3);
    }
    qsl = clampd(qsl, 0.7, 2.4);
    q1 = clampd(q1, 0.5, 3.0);
    q2 = clampd(q2 < q1 + 0.15 ? q1 + 0.15 : q2, q1 + 0.15, 5.0);
    q3 = clampd(q3 < q2 + 0.15 ? q2 + 0.15 : q3, q2 + 0.15, 8.0);
    p->sl = clampd(0.55 * ARM_SL[arm] + 0.45 * qsl, 0.7, 2.5);
    p->t1 = clampd(0.55 * ARM_T1[arm] + 0.45 * q1, 0.5, 4.0);
    p->t2 = clampd(0.55 * ARM_T2[arm] + 0.45 * q2, p->t1 + 0.2, 6.0);
    p->t3 = clampd(0.55 * ARM_T3[arm] + 0.45 * q3, p->t2 + 0.2, 8.0);
    double sum = 0;
    for (int i = 0; i < n; i++)
        sum += realized_r(&s[i], p->sl, p->t3);
    p->mean_r = n ? sum / n : 0;
}

static void train(const Sample *s, int n, Policy *p) {
    memset(p, 0, sizeof *p);
    p->n = n;
    if (n < MIN_N) {
        strcpy(p->source, "DEFAULT");
        p->arm = 0;
        p->sl = ARM_SL[0];
        p->t1 = ARM_T1[0];
        p->t2 = ARM_T2[0];
        p->t3 = ARM_T3[0];
        return;
    }
    int split = (int)(n * 0.7);
    if (split < MIN_N) split = n;
    int ucb = pick_ucb(s, split);
    int rl = reinforce(s, split);
    p->arm = rl;
    strcpy(p->source, "RL_UCB");
    p->ready = 1;
    blend(s, split, p->arm, p);
    if (n > split) {
        double sum = 0;
        int k = 0;
        for (int i = split; i < n; i++, k++)
            sum += realized_r(&s[i], p->sl, p->t3);
        p->oos_r = k ? sum / k : 0;
    } else {
        p->oos_r = p->mean_r;
    }
    (void)ucb;
}

static int write_policy(const char *path, const Policy *p) {
    FILE *f = fopen(path, "w");
    if (!f) return 0;
    fprintf(f, "ready,source,n,arm,sl_r,tp1_r,tp2_r,tp3_r,mean_r\n");
    fprintf(f, "%d,%s,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f\n", p->ready, p->source, p->n, p->arm, p->sl,
            p->t1, p->t2, p->t3, p->mean_r);
    fclose(f);
    return 1;
}

static void policy_path_from_csv(const char *csv, char *out, size_t cap) {
    strncpy(out, csv, cap - 1);
    out[cap - 1] = 0;
    char *slash = strrchr(out, '/');
#ifdef _WIN32
    char *bslash = strrchr(out, '\\');
    if (!slash || (bslash && bslash > slash)) slash = bslash;
#endif
    char *name = slash ? slash + 1 : out;
    if (strncmp(name, "BREAK100_learn_", 15) == 0) {
        memmove(name + 16, name + 15, strlen(name + 15) + 1);
        memcpy(name, "BREAK100_policy_", 16);
    } else {
        char tmp[1024];
        snprintf(tmp, sizeof tmp, "%s.policy.csv", csv);
        strncpy(out, tmp, cap - 1);
    }
}

#ifdef _WIN32
static int find_common_csv(char *found, size_t cap) {
    const char *app = getenv("APPDATA");
    if (!app) return 0;
    char glob[MAX_PATH];
    snprintf(glob, sizeof glob, "%s\\MetaQuotes\\Terminal\\Common\\Files\\BREAK100_learn_*.csv", app);
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(glob, &fd);
    if (h == INVALID_HANDLE_VALUE) return 0;
    snprintf(found, cap, "%s\\MetaQuotes\\Terminal\\Common\\Files\\%s", app, fd.cFileName);
    FILETIME best = fd.ftLastWriteTime;
    while (FindNextFileA(h, &fd)) {
        if (CompareFileTime(&fd.ftLastWriteTime, &best) > 0) {
            best = fd.ftLastWriteTime;
            snprintf(found, cap, "%s\\MetaQuotes\\Terminal\\Common\\Files\\%s", app, fd.cFileName);
        }
    }
    FindClose(h);
    return 1;
}
#endif

static void pause_out(void) {
    printf("\nPress Enter to close...");
    fflush(stdout);
    int c;
    while ((c = getchar()) != '\n' && c != EOF) {
    }
}

int main(int argc, char **argv) {
    printf("============================================\n");
    printf(" BREAK100 Policy Trainer  v1.41\n");
    printf(" Offline UCB + REINFORCE for SL/TP\n");
    printf(" Does NOT send broker orders. Not a profit claim.\n");
    printf("============================================\n\n");

    char csv[1024];
    csv[0] = 0;
    if (argc >= 2) {
        strncpy(csv, argv[1], sizeof csv - 1);
    }
#ifdef _WIN32
    else {
        if (find_common_csv(csv, sizeof csv))
            printf("Found latest EA log:\n  %s\n\n", csv);
    }
#endif
    if (!csv[0]) {
        printf("Drag BREAK100_learn_*.csv onto this exe, or type the full path:\n> ");
        if (!fgets(csv, sizeof csv, stdin)) return 1;
        char *nl = strchr(csv, '\n');
        if (nl) *nl = 0;
        if (csv[0] == '"' ) {
            size_t L = strlen(csv);
            if (L >= 2 && csv[L - 1] == '"') {
                csv[L - 1] = 0;
                memmove(csv, csv + 1, L - 1);
            }
        }
    }

    Sample *s = (Sample *)malloc(sizeof(Sample) * MAX_N);
    if (!s) return 2;
    int n = parse_csv(csv, s, MAX_N);
    if (n < 0) {
        printf("Cannot open:\n  %s\n", csv);
        printf("Put the EA on a chart first. It writes:\n");
        printf("  %%APPDATA%%\\MetaQuotes\\Terminal\\Common\\Files\\BREAK100_learn_<symbol>.csv\n");
        free(s);
        pause_out();
        return 3;
    }
    printf("Loaded %d closed labels from\n  %s\n\n", n, csv);
    if (n < MIN_N) {
        printf("Need at least %d labels (have %d). Leave the EA running, then train again.\n", MIN_N, n);
        free(s);
        pause_out();
        return 4;
    }

    Policy p;
    train(s, n, &p);
    printf("Train  n=%d  source=%s  arm=%s (%d)\n", p.n, p.source, ARM_ID[p.arm], p.arm);
    printf("SL/hw  %.3f\n", p.sl);
    printf("TP/hw  %.3f / %.3f / %.3f\n", p.t1, p.t2, p.t3);
    printf("In-sample mean R   %.4f\n", p.mean_r);
    printf("Walk-forward OOS R %.4f\n", p.oos_r);
    printf("\nOOS R is a research score on held-out labels. It is not expected profit.\n\n");

    char out[1024];
    policy_path_from_csv(csv, out, sizeof out);
    if (!write_policy(out, &p)) {
        printf("Could not write %s\n", out);
        free(s);
        pause_out();
        return 5;
    }
    printf("Wrote policy:\n  %s\n\n", out);
    printf("If this is already in Common\\Files, restart the EA (remove + attach).\n");
    printf("Otherwise copy the policy csv into:\n");
    printf("  %%APPDATA%%\\MetaQuotes\\Terminal\\Common\\Files\\\n");
    printf("Keep InpUseLearner = true. AutoTrading stays OFF.\n");
    free(s);
    pause_out();
    return 0;
}
