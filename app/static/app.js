document.addEventListener("submit", function (event) {
    const form = event.target;
    const submitter = event.submitter;
    const message = form.dataset.confirm || submitter?.dataset.confirm;

    if (message && !window.confirm(message)) {
        event.preventDefault();
    }
});
