document.querySelectorAll("[data-contact-email]").forEach((button) => {
  button.addEventListener("click", () => {
    const address = String.fromCharCode(
      99, 111, 110, 116, 97, 99, 116, 64, 115, 104, 105, 102, 116, 111, 110, 101, 46,
      97, 105
    );
    window.location.href = `mailto:${address}`;
  });
});
