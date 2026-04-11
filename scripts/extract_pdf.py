import fitz
import sys

def main():
    if len(sys.argv) != 3:
        print("Usage: python extract_pdf.py <input.pdf> <output.txt>")
        return
    
    pdf_path = sys.argv[1]
    txt_path = sys.argv[2]
    
    try:
        doc = fitz.open(pdf_path)
        with open(txt_path, 'w', encoding='utf-8') as f:
            for page in doc:
                f.write(page.get_text())
        print(f"Successfully extracted text to {txt_path}")
    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    main()
