"""OCR module: image preprocessing and text extraction via Tesseract 5."""

import base64
import io
import os
import sys
import cv2
import numpy as np
import pytesseract
from PIL import Image
import fitz  # PyMuPDF
from pathlib import Path
from config import OCR_LANGUAGES, MIN_TEXT_LENGTH_PER_PAGE
import logging

logger = logging.getLogger(__name__)

# Auto-detect Tesseract on Windows
if sys.platform == "win32":
    _win_tesseract = r"C:\Program Files\Tesseract-OCR\tesseract.exe"
    if os.path.isfile(_win_tesseract):
        pytesseract.pytesseract.tesseract_cmd = _win_tesseract
        logger.info("Tesseract found at %s", _win_tesseract)


def preprocess_image(image: np.ndarray) -> np.ndarray:
    """Apply full preprocessing pipeline to an image for optimal OCR results.

    Pipeline steps:
        1. Convert to grayscale (if not already)
        2. CLAHE contrast enhancement
        3. Deskew via minAreaRect on largest contour
        4. Light Gaussian blur for noise reduction
        5. Adaptive Gaussian thresholding

    Args:
        image: Input image as a numpy array (BGR or grayscale).

    Returns:
        Preprocessed binary image ready for OCR.
    """
    # 1. Convert to grayscale if needed
    if len(image.shape) == 3:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    else:
        gray = image.copy()

    # 2. CLAHE (Contrast Limited Adaptive Histogram Equalization)
    clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
    enhanced = clahe.apply(gray)

    # 3. Deskew using minAreaRect on the largest contour
    enhanced = _deskew(enhanced)

    # 4. Light Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(enhanced, (3, 3), 0)

    # 5. Adaptive threshold (Gaussian method)
    binary = cv2.adaptiveThreshold(
        blurred,
        255,
        cv2.ADAPTIVE_THRESH_GAUSSIAN_C,
        cv2.THRESH_BINARY,
        11,
        2,
    )

    return binary


def _deskew(image: np.ndarray) -> np.ndarray:
    """Deskew an image by detecting rotation angle from the largest contour.

    Uses cv2.minAreaRect on the largest-area contour to determine the skew
    angle, then rotates the image to straighten it.

    Args:
        image: Grayscale image as a numpy array.

    Returns:
        Deskewed grayscale image.
    """
    # Threshold to find contours
    thresh = cv2.threshold(image, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)[1]
    contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    if not contours:
        return image

    # Find the contour with the largest area
    largest_contour = max(contours, key=cv2.contourArea)

    # Need at least 5 points for minAreaRect to be meaningful
    if cv2.contourArea(largest_contour) < 100:
        return image

    rect = cv2.minAreaRect(largest_contour)
    angle = rect[2]

    # Normalize angle: minAreaRect returns angles in [-90, 0)
    # We want to correct small skews, not 90-degree rotations
    if angle < -45:
        angle = 90 + angle
    elif angle > 45:
        angle = angle - 90

    # Only deskew if the angle is meaningful but not too extreme
    if abs(angle) < 0.5 or abs(angle) > 45:
        return image

    h, w = image.shape[:2]
    center = (w // 2, h // 2)
    rotation_matrix = cv2.getRotationMatrix2D(center, angle, 1.0)
    rotated = cv2.warpAffine(
        image, rotation_matrix, (w, h),
        flags=cv2.INTER_CUBIC,
        borderMode=cv2.BORDER_REPLICATE,
    )

    logger.debug("Deskewed image by %.2f degrees", angle)
    return rotated


def extract_text_from_image(image_path: str) -> str:
    """Extract text from an image file using Tesseract OCR with preprocessing.

    Args:
        image_path: Path to the image file on disk.

    Returns:
        Extracted text string.

    Raises:
        FileNotFoundError: If the image file does not exist.
        RuntimeError: If OpenCV cannot load the image.
    """
    path = Path(image_path)
    if not path.exists():
        raise FileNotFoundError(f"Image file not found: {image_path}")

    image = cv2.imread(str(path))
    if image is None:
        raise RuntimeError(f"Failed to load image with OpenCV: {image_path}")

    processed = preprocess_image(image)
    text = pytesseract.image_to_string(processed, lang=OCR_LANGUAGES)
    text = text.strip()

    logger.info("Extracted %d characters from image: %s", len(text), path.name)
    return text


def extract_text_from_pdf(pdf_path: str) -> str:
    """Extract text from a PDF, falling back to OCR for scanned pages.

    For each page, native text extraction is attempted first. If the page
    yields fewer than ``MIN_TEXT_LENGTH_PER_PAGE`` characters, it is treated
    as a scanned page and processed through the OCR pipeline (render at
    300 DPI → preprocess → Tesseract).

    Args:
        pdf_path: Path to the PDF file on disk.

    Returns:
        Concatenated text from all pages, separated by page markers.

    Raises:
        FileNotFoundError: If the PDF file does not exist.
    """
    path = Path(pdf_path)
    if not path.exists():
        raise FileNotFoundError(f"PDF file not found: {pdf_path}")

    doc = fitz.open(str(path))
    all_pages_text: list[str] = []

    for page_num in range(len(doc)):
        page = doc[page_num]

        # Try native text extraction first
        native_text = page.get_text().strip()

        if len(native_text) >= MIN_TEXT_LENGTH_PER_PAGE:
            page_text = native_text
            logger.debug(
                "Page %d: native text extraction (%d chars)",
                page_num + 1, len(native_text),
            )
        else:
            # Scanned page — render to image and OCR
            logger.debug(
                "Page %d: native text too short (%d chars), falling back to OCR",
                page_num + 1, len(native_text),
            )
            pix = page.get_pixmap(dpi=300)
            pil_image = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)
            img_array = np.array(pil_image)
            processed = preprocess_image(img_array)
            page_text = pytesseract.image_to_string(processed, lang=OCR_LANGUAGES).strip()
            logger.debug("Page %d: OCR extracted %d chars", page_num + 1, len(page_text))

        all_pages_text.append(page_text)

    doc.close()

    # Join pages with separators
    full_text = ""
    for i, page_text in enumerate(all_pages_text):
        if i > 0:
            full_text += f"\n\n--- Page {i + 1} ---\n\n"
        else:
            full_text += f"--- Page 1 ---\n\n"
        full_text += page_text

    logger.info(
        "Extracted %d characters from %d-page PDF: %s",
        len(full_text), len(all_pages_text), path.name,
    )
    return full_text


def extract_text(file_path: str) -> str:
    """Extract text from a document file (PDF or image).

    Dispatches to the appropriate extraction function based on file extension.

    Args:
        file_path: Path to the document file on disk.

    Returns:
        Extracted text string.

    Raises:
        ValueError: If the file extension is not supported.
        FileNotFoundError: If the file does not exist.
    """
    ext = Path(file_path).suffix.lower()

    if ext == ".pdf":
        return extract_text_from_pdf(file_path)
    elif ext in {".jpg", ".jpeg", ".png", ".tiff", ".webp"}:
        return extract_text_from_image(file_path)
    else:
        raise ValueError(
            f"Unsupported file format '{ext}'. "
            f"Supported formats: .pdf, .jpg, .jpeg, .png, .tiff, .webp"
        )


def extract_images_as_base64(
    file_path: str,
    max_pages: int = 3,
    dpi: int = 200,
    jpeg_quality: int = 80,
) -> list[str]:
    """Extract document pages as base64-encoded JPEG images for LLM vision.

    For PDFs each page (up to *max_pages*) is rendered at the given DPI and
    encoded as JPEG.  For standalone image files, the single image is loaded
    and re-encoded as JPEG.

    Args:
        file_path: Path to the document file on disk.
        max_pages: Maximum number of PDF pages to extract (default 3).
        dpi: Resolution for PDF page rendering (default 200).
        jpeg_quality: JPEG compression quality 1-100 (default 80).

    Returns:
        List of base64-encoded JPEG strings (without data-URI prefix).
        Returns an empty list if the file format is unsupported or on error.
    """
    path = Path(file_path)
    if not path.exists():
        logger.warning("Cannot extract images — file not found: %s", file_path)
        return []

    ext = path.suffix.lower()
    images_b64: list[str] = []

    try:
        if ext == ".pdf":
            doc = fitz.open(str(path))
            page_count = min(len(doc), max_pages)
            for page_num in range(page_count):
                page = doc[page_num]
                pix = page.get_pixmap(dpi=dpi)
                pil_image = Image.frombytes("RGB", [pix.width, pix.height], pix.samples)

                buf = io.BytesIO()
                pil_image.save(buf, format="JPEG", quality=jpeg_quality)
                b64 = base64.b64encode(buf.getvalue()).decode("ascii")
                images_b64.append(b64)

                logger.debug(
                    "Page %d rendered to JPEG (%d×%d, %d KB base64)",
                    page_num + 1,
                    pix.width,
                    pix.height,
                    len(b64) // 1024,
                )
            doc.close()

        elif ext in {".jpg", ".jpeg", ".png", ".tiff", ".webp"}:
            pil_image = Image.open(str(path))
            if pil_image.mode != "RGB":
                pil_image = pil_image.convert("RGB")

            buf = io.BytesIO()
            pil_image.save(buf, format="JPEG", quality=jpeg_quality)
            b64 = base64.b64encode(buf.getvalue()).decode("ascii")
            images_b64.append(b64)

            logger.debug(
                "Image encoded to JPEG (%d×%d, %d KB base64)",
                pil_image.width,
                pil_image.height,
                len(b64) // 1024,
            )

        else:
            logger.warning(
                "Cannot extract images — unsupported format '%s'", ext,
            )

    except Exception:
        logger.exception("Failed to extract images from %s", file_path)

    logger.info(
        "Extracted %d image(s) from %s for vision analysis",
        len(images_b64),
        path.name,
    )
    return images_b64
