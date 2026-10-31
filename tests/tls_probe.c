/* Exercises the exact curl/Mbed TLS versions independently of Apple's TLS stack. */
#include <curl/curl.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
static size_t discard(char *data, size_t size, size_t count, void *context) {
    (void)data;
    *(size_t *)context += size * count;
    return size * count;
}
static int transfer(const char *url, const char *roots) {
    CURL *curl = curl_easy_init();
    size_t received = 0;
    char error[CURL_ERROR_SIZE] = {0};
    curl_easy_setopt(curl, CURLOPT_URL, url);
    curl_easy_setopt(curl, CURLOPT_CAINFO, roots);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYPEER, 1L);
    curl_easy_setopt(curl, CURLOPT_SSL_VERIFYHOST, 2L);
    curl_easy_setopt(curl, CURLOPT_SSLVERSION, CURL_SSLVERSION_TLSv1_2);
    curl_easy_setopt(curl, CURLOPT_PROTOCOLS_STR, "http,https");
    curl_easy_setopt(curl, CURLOPT_REDIR_PROTOCOLS_STR, "https");
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_MAXREDIRS, 10L);
    curl_easy_setopt(curl, CURLOPT_PROXY, "");
    curl_easy_setopt(curl, CURLOPT_RANGE, "0-4095");
    curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 20L);
    curl_easy_setopt(curl, CURLOPT_TIMEOUT, 45L);
    curl_easy_setopt(curl, CURLOPT_ERRORBUFFER, error);
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, discard);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &received);
    CURLcode result = curl_easy_perform(curl);
    long status = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &status);
    printf("%s\nresult=%d HTTP=%ld bytes=%lu %s\n", curl_version(), result, status, (unsigned long)received, error);
    curl_easy_cleanup(curl);
    return result == CURLE_OK && status >= 200 && status < 300 && received > 0 ? 0 : (int)(result ? result : 1);
}
struct job { const char *url; const char *roots; int result; };
static void *worker(void *context) {
    struct job *job = context;
    job->result = transfer(job->url, job->roots);
    return NULL;
}
int main(int argc, char **argv) {
    if (argc != 3 && argc != 4) return 2;
    curl_global_init(CURL_GLOBAL_DEFAULT);
    int result = 0;
    if (argc == 4) {
        pthread_t threads[3];
        struct job jobs[3];
        for (int i = 0; i < 3; ++i) {
            jobs[i] = (struct job){argv[1], argv[2], 1};
            if (pthread_create(&threads[i], NULL, worker, &jobs[i])) return 3;
        }
        for (int i = 0; i < 3; ++i) { pthread_join(threads[i], NULL); if (jobs[i].result) result = jobs[i].result; }
    } else result = transfer(argv[1], argv[2]);
    curl_global_cleanup();
    return result;
}
