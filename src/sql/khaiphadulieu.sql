/* ============================================================================
   FILE 2/2 — KHAI PHÁ DỮ LIỆU BẰNG T-SQL  (SQL Server 2016 SP1 trở lên)
   Đề tài        : Analyzing and Predicting Customer Churn in Credit Card Services
   Biến trọng tâm: Total_Trans_Ct (tổng số lượt giao dịch trong 12 tháng)
   Điều kiện     : đã chạy FILE 1 thành công (Customers và Card_Activity đều 10.127 dòng)

   CẤU TRÚC
     BỐN CÂU HỎI CHÍNH (mạch: có khác biệt? -> hình dạng? -> có bền vững? -> hành động?)
       Q1  Hai nhóm churn khác nhau thế nào?      trung bình, trung vị, min, max
       Q2  Hình dạng của mối quan hệ với          churn theo dải số lượt giao dịch
           Total_Trans_Ct là gì?
       Q3  Mẫu hình đó có bền vững giữa các       phân tầng theo giới tính, hạng thẻ, độ tuổi;
           nhóm khách không?                      kiểm định z-score; kiểm soát biến gây nhiễu
       Q4  Nên can thiệp vào ai?                  điểm rủi ro, precision/recall, watch-list
     Chuẩn bị : Q0  Hồ sơ chất lượng dữ liệu (quy mô, churn nền, giá trị 'Unknown')
     Phụ lục  : A   Thu nhập x Hạng thẻ (HAVING; kiểm tra giả thuyết "nâng hạng thẻ")
     Cuối file: Tổng hợp và Hạn chế (đưa thẳng vào báo cáo)

   QUY ƯỚC
     - Attrition_Flag: 1 = Attrited (rời bỏ), 0 = Existing (ở lại).
       Churn rate = % khách có Attrition_Flag = 1.
       Churn nền toàn tập = 1.627 / 10.127 = 16,07%.
     - Precision = % khách bị cảnh báo mà thực sự rời bỏ.
       Recall    = % khách rời bỏ mà cảnh báo bắt được.
       Lift      = Precision / churn nền (lift 3 = khả năng rời bỏ gấp 3 lần mức trung bình).
     - Mỗi truy vấn là một khối kết thúc bằng GO: bôi đen riêng từng khối rồi bấm F5 là chạy được.
     - Phần diễn giải dùng dấu phẩy thập phân kiểu Việt Nam (16,07%); bảng "Kết quả tham chiếu"
       giữ nguyên dạng SQL Server hiển thị (16.07) để dễ đối chiếu khi chạy.
       Mọi con số trong file đã được đối chiếu trực tiếp với BankChurners_clean.csv.
     - Mọi kết quả chỉ MÔ TẢ mối liên hệ, không chứng minh quan hệ nhân quả
       (xem "Hạn chế" ở cuối file).
   ============================================================================ */

USE Bankchurn;
GO


/* ============================================================================
   Q0 — HỒ SƠ CHẤT LƯỢNG DỮ LIỆU
   Business Question:
   "Dữ liệu có đủ sạch và đủ cân đối để phân tích không? Tỉ lệ churn nền là bao nhiêu?"

   SQL Techniques: COUNT/SUM/CAST, CASE WHEN bên trong hàm tổng hợp,
                   CROSS APPLY (VALUES ...) để "xoay" 3 cột thành 3 dòng (kỹ thuật unpivot).
   ============================================================================ */

-- 0A. Quy mô và churn nền
SELECT COUNT(*)                                                     AS Num_Customers,
       SUM(Attrition_Flag)                                          AS Num_Attrited,
       CAST(100.0 * SUM(Attrition_Flag) / COUNT(*) AS DECIMAL(5,2)) AS Base_Churn_Rate_Pct
FROM dbo.Customers;

-- 0B. Tỉ lệ 'Unknown' ở 3 cột phân loại, và churn của nhóm Unknown so với nhóm đã biết
SELECT u.Column_Name,
       SUM(CASE WHEN u.Val = 'Unknown' THEN 1 ELSE 0 END)                        AS Num_Unknown,
       CAST(100.0 * SUM(CASE WHEN u.Val = 'Unknown' THEN 1 ELSE 0 END)
                  / COUNT(*)                                  AS DECIMAL(5,2))   AS Pct_Unknown,
       CAST(100.0 * SUM(CASE WHEN u.Val = 'Unknown' THEN c.Attrition_Flag ELSE 0 END)
                  / SUM(CASE WHEN u.Val = 'Unknown' THEN 1 ELSE 0 END)
                                                              AS DECIMAL(5,2))   AS Churn_Pct_Unknown,
       CAST(100.0 * SUM(CASE WHEN u.Val <> 'Unknown' THEN c.Attrition_Flag ELSE 0 END)
                  / SUM(CASE WHEN u.Val <> 'Unknown' THEN 1 ELSE 0 END)
                                                              AS DECIMAL(5,2))   AS Churn_Pct_Known
FROM dbo.Customers AS c
CROSS APPLY (VALUES ('Education_Level', c.Education_Level),     -- mỗi khách -> 3 dòng (mỗi cột 1 dòng)
                    ('Marital_Status',  c.Marital_Status),
                    ('Income_Category', c.Income_Category)) AS u (Column_Name, Val)
GROUP BY u.Column_Name
ORDER BY Pct_Unknown DESC;
GO

/*
Kết quả tham chiếu
  0A:  Num_Customers = 10127 | Num_Attrited = 1627 | Base_Churn_Rate_Pct = 16.07
  0B:  Column_Name       Num_Unknown  Pct_Unknown  Churn_Pct_Unknown  Churn_Pct_Known
       Education_Level   1519         15.00        16.85              15.93
       Income_Category   1112         10.98        16.82              15.97
       Marital_Status     749          7.40        17.22              15.97

Business Insight
  - Có 10.127 khách, 1.627 khách rời bỏ => churn nền 16,07% (khoảng 1 rời bỏ : 5 ở lại).
    Dữ liệu mất cân bằng: một "mô hình" luôn đoán 'ở lại' đã đúng 83,9% mà không bắt được khách
    rời bỏ nào. Vì vậy ở phần mô hình phải đánh giá bằng precision/recall (hoặc PR-AUC),
    không chỉ accuracy.
  - 'Unknown' chiếm 15,00% (Education_Level), 10,98% (Income_Category), 7,40% (Marital_Status).
    Nhóm Unknown có churn xấp xỉ mức nền (16,8-17,2% so với 15,9-16,0% ở nhóm đã biết, chênh
    không quá 1,3 điểm %) => giữ lại như một nhóm riêng, không xóa dòng, không điền bừa.
    Ngoại lệ: Phụ lục A loại 'Unknown' khỏi so sánh theo thu nhập, vì nó không phải một mức thu nhập.
    Lưu ý thêm (Q3C): 95% khách 'Unknown' về thu nhập là nữ, tức là thiếu thông tin KHÔNG ngẫu nhiên.
*/


/* ============================================================================
   Q1 — THỐNG KÊ CƠ BẢN THEO NHÓM CHURN
   Business Question:
   "Khách rời bỏ (Attrited) và khách ở lại (Existing) khác nhau thế nào về hành vi giao
    dịch: số lượt (Total_Trans_Ct), giá trị (Total_Trans_Amt) và xu hướng Q4/Q1?"

   SQL Techniques: INNER JOIN, CTE, GROUP BY, COUNT/AVG/MIN/MAX,
                   PERCENTILE_CONT (trung vị), window function SUM() OVER ().
   Lưu ý kỹ thuật: AVG trên cột INT trong T-SQL trả về SỐ NGUYÊN (cắt phần thập phân),
                   nên phải viết AVG(1.0 * cột) để có số thập phân đúng.
   ============================================================================ */
WITH Joined AS (
    SELECT c.Attrition_Flag,
           a.Total_Trans_Ct,
           a.Total_Trans_Amt,
           a.Total_Ct_Chng_Q4_Q1
    FROM dbo.Customers AS c
    INNER JOIN dbo.Card_Activity AS a
            ON a.CLIENTNUM = c.CLIENTNUM
),
Medians AS (
    -- PERCENTILE_CONT trong T-SQL chỉ chạy được như hàm cửa sổ (có OVER), nên dùng
    -- DISTINCT để mỗi nhóm churn chỉ còn đúng 1 dòng trung vị.
    SELECT DISTINCT
           Attrition_Flag,
           CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Total_Trans_Ct)
                OVER (PARTITION BY Attrition_Flag) AS DECIMAL(8,1))   AS Median_Trans_Ct,
           CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY Total_Trans_Amt)
                OVER (PARTITION BY Attrition_Flag) AS DECIMAL(10,1))  AS Median_Trans_Amt
    FROM Joined
)
SELECT j.Attrition_Flag,
       CASE j.Attrition_Flag
            WHEN 0 THEN N'Existing (ở lại)'
            WHEN 1 THEN N'Attrited (rời bỏ)'
       END                                                         AS Segment_Name,
       COUNT(*)                                                    AS Num_Customers,
       CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)) AS Pct_Of_Total,
       CAST(AVG(1.0 * j.Total_Trans_Ct)  AS DECIMAL(6,2))          AS Avg_Trans_Ct,
       m.Median_Trans_Ct,
       MIN(j.Total_Trans_Ct)                                       AS Min_Trans_Ct,
       MAX(j.Total_Trans_Ct)                                       AS Max_Trans_Ct,
       CAST(AVG(1.0 * j.Total_Trans_Amt) AS DECIMAL(10,2))         AS Avg_Trans_Amt,
       m.Median_Trans_Amt,
       CAST(AVG(j.Total_Ct_Chng_Q4_Q1)   AS DECIMAL(6,3))          AS Avg_Ct_Chng_Q4_Q1
FROM Joined AS j
INNER JOIN Medians AS m
        ON m.Attrition_Flag = j.Attrition_Flag
GROUP BY j.Attrition_Flag, m.Median_Trans_Ct, m.Median_Trans_Amt
ORDER BY j.Attrition_Flag;
GO

/*
Kết quả tham chiếu
  Flag Segment_Name       Num   Pct    Avg_Ct Med_Ct Min Max Avg_Amt  Med_Amt Avg_Chng
  0    Existing (ở lại)   8500  83.93  68.67  71.0   11  139 4654.66  4100.0  0.742
  1    Attrited (rời bỏ)  1627  16.07  44.93  43.0   10   94 3095.03  2329.0  0.554

Business Insight
  - Khách rời bỏ giao dịch ít hơn rõ rệt: trung bình 44,93 so với 68,67 lượt/năm (-34,6%);
    trung vị 43 so với 71 lượt (-39,4%). Giá trị chi tiêu cũng thấp tương ứng: trung bình
    3.095 so với 4.655 (-33,5%), trung vị 2.329 so với 4.100 (-43,2%).
  - Xu hướng Q4/Q1 của nhóm rời bỏ là 0,55 so với 0,74 (khoảng -25%): họ đã giảm dùng thẻ
    trong năm trước khi rời đi.
  - Trung vị chênh nhiều hơn trung bình (-39,4% so với -34,6%), cho thấy cả phân phối của nhóm
    rời bỏ dịch xuống thấp, không chỉ do vài trường hợp cá biệt kéo lệch giá trị trung bình.
  - Tuy nhiên hai nhóm chồng lấn rất nhiều (Attrited: 10-94 lượt; Existing: 11-139 lượt),
    nên một biến đơn lẻ không đủ để tách hai nhóm => cần kết hợp nhiều tín hiệu (Q4).
  - Đây là mối liên hệ ĐỒNG THỜI trong cùng 12 tháng, chưa phải bằng chứng "dự báo sớm":
    xem Hạn chế (1) ở cuối file.
*/


/* ============================================================================
   Q2 — CHURN THEO DẢI SỐ LƯỢT GIAO DỊCH
   Business Question:
   "Tỉ lệ rời bỏ thay đổi thế nào khi Total_Trans_Ct rơi vào từng dải 10 lượt?
    Có ngưỡng nào đủ rõ để dùng làm cảnh báo không?"

   SQL Techniques: CTE, CASE WHEN (rời rạc hóa biến liên tục thành dải), GROUP BY,
                   window function lồng aggregate SUM(SUM()) OVER ().
   Vì sao dải 10 lượt: bản trước chia 4 dải thô (<40, 40-60, 61-80, >80) nên che mất
   hình dạng thật của mối quan hệ (đỉnh churn nằm trong dải 41-50).
   ============================================================================ */
WITH Banded AS (
    SELECT c.Attrition_Flag,
           a.Total_Ct_Chng_Q4_Q1,
           CASE
               WHEN a.Total_Trans_Ct <= 30 THEN '01. <= 30'
               WHEN a.Total_Trans_Ct <= 40 THEN '02. 31-40'
               WHEN a.Total_Trans_Ct <= 50 THEN '03. 41-50'
               WHEN a.Total_Trans_Ct <= 60 THEN '04. 51-60'
               WHEN a.Total_Trans_Ct <= 70 THEN '05. 61-70'
               WHEN a.Total_Trans_Ct <= 80 THEN '06. 71-80'
               WHEN a.Total_Trans_Ct <= 90 THEN '07. 81-90'
               ELSE                             '08. > 90'
           END AS Trans_Band
    FROM dbo.Customers AS c
    INNER JOIN dbo.Card_Activity AS a
            ON a.CLIENTNUM = c.CLIENTNUM
)
SELECT Trans_Band,
       COUNT(*)            AS Num_Customers,
       SUM(Attrition_Flag) AS Num_Attrited,
       CAST(100.0 * SUM(Attrition_Flag) / COUNT(*)                          AS DECIMAL(5,2)) AS Churn_Rate_Pct,
       CAST(100.0 * SUM(Attrition_Flag) / SUM(SUM(Attrition_Flag)) OVER () AS DECIMAL(5,2)) AS Pct_Of_All_Attrited,
       CAST(AVG(Total_Ct_Chng_Q4_Q1) AS DECIMAL(6,3))                                       AS Avg_Ct_Chng_Q4_Q1
FROM Banded
GROUP BY Trans_Band
ORDER BY Trans_Band;
GO

/*
Kết quả tham chiếu
  Trans_Band  Num_Customers  Num_Attrited  Churn_Rate_Pct  Pct_Of_All_Attrited  Avg_Ct_Chng_Q4_Q1
  01. <= 30        698           204          29.23            12.54               0.754
  02. 31-40       1240           407          32.82            25.02               0.629
  03. 41-50       1190           576          48.40            35.40               0.628
  04. 51-60        919           204          22.20            12.54               0.732
  05. 61-70       1641           125           7.62             7.68               0.719
  06. 71-80       1889            80           4.24             4.92               0.752
  07. 81-90       1434            29           2.02             1.78               0.750
  08. > 90        1116             2           0.18             0.12               0.726

Business Insight
  - Mối quan hệ KHÔNG đơn điệu: churn đạt đỉnh ở dải 41-50 lượt (48,40%) và thấp hơn ở dải thấp
    nhất <= 30 lượt (29,23%). Không nên mô tả đơn giản là "càng ít giao dịch càng dễ rời bỏ".
  - Có thể chia thành 3 vùng:
      (a) <= 50 lượt : 3.128 khách (30,9% tệp), churn 37,95%, chứa 72,96% tổng số khách rời bỏ;
      (b) 51-60 lượt : vùng chuyển tiếp, churn 22,20%;
      (c) >= 61 lượt : 6.080 khách, churn chỉ 3,88%.
    Mức sụt mạnh nhất nằm giữa dải 41-50 và 51-60 (48,40% -> 22,20%), rồi tiếp tục giảm ở 61-70.
  - Giả thuyết (CHƯA kiểm định): dải <= 30 có xu hướng giao dịch ổn định hơn (Avg_Ct_Chng_Q4_Q1
    = 0,754 so với 0,629 và 0,628 ở hai dải 31-40 và 41-50), tức "dùng ít nhưng ổn định" ít nguy
    hiểm hơn "đang tụt dốc". Nếu đúng thì biến xu hướng (Total_Ct_Chng_Q4_Q1) quan trọng không
    kém biến mức độ (Total_Trans_Ct); Q4 khai thác tiếp ý này.
  - Ngưỡng vận hành "Total_Trans_Ct <= 60" (khoảng 5 lượt/tháng) bắt được 85,49% khách rời bỏ
    (1.391 / 1.627 khách; cộng 4 dải đầu của cột Pct_Of_All_Attrited ra 85,50% do làm tròn từng
    dải) nhưng churn trong nhóm này chỉ 34,37%, tức gần 2/3 số khách bị gắn cờ là báo động giả.
    Vì vậy cần kết hợp thêm tín hiệu (Q4).
  - Hệ quả cho phần mô hình: quan hệ phi tuyến, nên ưu tiên mô hình dạng cây / ensemble hoặc
    rời rạc hóa biến, thay vì chỉ dùng hồi quy tuyến tính trên biến thô.
  - Câu hỏi tiếp theo (Q3): ba vùng <= 50, 51-60, >= 61 lượt có đúng với mọi nhóm khách không?
*/


/* ============================================================================
   Q3 — MẪU HÌNH CÓ BỀN VỮNG GIỮA CÁC NHÓM KHÁCH HÀNG?  (PHÂN TẦNG)
   Business Question:
   "Mối liên hệ giữa Total_Trans_Ct và churn (Q2) có đúng như nhau với mọi nhóm khách -
    theo giới tính, hạng thẻ, độ tuổi - hay có nhóm mà quy luật yếu đi hoặc đảo chiều?"

   Giả thuyết (viết TRƯỚC khi chạy):
     H1: ở mọi nhóm, churn giảm dần theo thứ tự vùng Z1 > Z2 > Z3.
     H2: ở cùng một vùng, mức churn của các nhóm chênh nhau không đáng kể.
   Ba vùng giao dịch lấy từ Q2:
     Z1 = <= 50 lượt (rủi ro cao) | Z2 = 51-60 lượt (chuyển tiếp) | Z3 = >= 61 lượt (an toàn)

   Vì sao phải phân tầng: số liệu gộp có thể che mất khác biệt giữa các nhóm (xem Q3B).
   Mỗi "nhóm khách x vùng giao dịch" gọi là một ô; ô dưới 50 khách bị loại bằng HAVING vì quá nhiễu.

   Ba truy vấn đi theo một mạch:
     Q3A  mô tả     : churn của từng nhóm ở từng vùng (có nhất quán không?)
     Q3B  kiểm định : chênh lệch nữ - nam có ý nghĩa thống kê không? (z-score)
     Q3C  kiểm soát : chênh lệch đó có phải do thu nhập (biến gây nhiễu) không?

   SQL Techniques: VIEW, CTE, CROSS APPLY (VALUES ...), GROUP BY + HAVING,
                   pivot bằng MAX(CASE ...), self-join một CTE (so nữ với nam),
                   SQRT (z-score), NULLIF (tránh chia cho 0).
   ============================================================================ */

-- Q3-SETUP. View gắn cho mỗi khách nhóm tuổi (Age_Band) và vùng giao dịch (Trans_Zone).
-- Định nghĩa một lần, Q3A-Q3C dùng lại (tuổi nhỏ nhất trong dữ liệu là 26 nên '18-34' thực chất là 26-34).
CREATE OR ALTER VIEW dbo.vw_Customer_Segments
AS
SELECT c.CLIENTNUM,
       c.Attrition_Flag,
       c.Gender,
       c.Card_Category,
       c.Income_Category,
       CASE WHEN c.Customer_Age <= 34 THEN '18-34'
            WHEN c.Customer_Age <= 44 THEN '35-44'
            WHEN c.Customer_Age <= 54 THEN '45-54'
            WHEN c.Customer_Age <= 64 THEN '55-64'
            ELSE                           '65+'
       END AS Age_Band,
       a.Total_Trans_Ct,
       CASE WHEN a.Total_Trans_Ct <= 50 THEN 'Z1'
            WHEN a.Total_Trans_Ct <= 60 THEN 'Z2'
            ELSE                             'Z3'
       END AS Trans_Zone
FROM dbo.Customers AS c
INNER JOIN dbo.Card_Activity AS a
        ON a.CLIENTNUM = c.CLIENTNUM;
GO


/* ----------------------------------------------------------------------------
   Q3A — CHURN CỦA TỪNG NHÓM Ở TỪNG VÙNG GIAO DỊCH
   Dòng đầu ("Toàn bộ") là mức chuẩn để so sánh. Ô dưới 50 khách để trống (NULL).
   Muốn thêm một chiều phân tích (vd. Income_Category) chỉ cần thêm một dòng vào VALUES.
   ---------------------------------------------------------------------------- */
WITH Cells AS (
    SELECT s.Dim_No, s.Dimension, s.Segment, v.Trans_Zone,
           COUNT(*)              AS N,
           SUM(v.Attrition_Flag) AS Attrited
    FROM dbo.vw_Customer_Segments AS v
    CROSS APPLY (VALUES (0, N'Toàn bộ',   N'Tất cả'),            -- mỗi khách -> 4 dòng (1 dòng cho mỗi chiều)
                        (1, N'Giới tính', v.Gender),
                        (2, N'Hạng thẻ',  v.Card_Category),
                        (3, N'Độ tuổi',   v.Age_Band)) AS s (Dim_No, Dimension, Segment)
    GROUP BY s.Dim_No, s.Dimension, s.Segment, v.Trans_Zone
    HAVING COUNT(*) >= 50
)
SELECT Dimension,
       Segment,
       MAX(CASE WHEN Trans_Zone = 'Z1' THEN N END)                                            AS N_Z1,
       MAX(CASE WHEN Trans_Zone = 'Z1' THEN CAST(100.0 * Attrited / N AS DECIMAL(5,2)) END)  AS Churn_Z1_Pct,
       MAX(CASE WHEN Trans_Zone = 'Z2' THEN N END)                                            AS N_Z2,
       MAX(CASE WHEN Trans_Zone = 'Z2' THEN CAST(100.0 * Attrited / N AS DECIMAL(5,2)) END)  AS Churn_Z2_Pct,
       MAX(CASE WHEN Trans_Zone = 'Z3' THEN N END)                                            AS N_Z3,
       MAX(CASE WHEN Trans_Zone = 'Z3' THEN CAST(100.0 * Attrited / N AS DECIMAL(5,2)) END)  AS Churn_Z3_Pct
FROM Cells
GROUP BY Dim_No, Dimension, Segment
ORDER BY Dim_No, Segment;
GO

/*
Kết quả tham chiếu (Q3A)
  Dimension  Segment  N_Z1   Churn_Z1_Pct  N_Z2   Churn_Z2_Pct  N_Z3   Churn_Z3_Pct
  Toàn bộ    Tất cả   3128      37.95       919       22.20      6080        3.88
  Giới tính  F        1473      49.83       416       26.92      3469        2.42
  Giới tính  M        1655      27.37       503       18.29      2611        5.82
  Hạng thẻ   Blue     2999      37.98       863       22.25      5574        3.37
  Hạng thẻ   Gold     NULL      NULL       NULL       NULL         94       13.83
  Hạng thẻ   Silver    109      37.61        50       18.00       396        8.08
  Độ tuổi    18-34     229      22.27        91       12.09       415        9.40
  Độ tuổi    35-44    1002      39.42       330       24.55      2108        3.42
  Độ tuổi    45-54    1214      44.32       375       23.73      2753        3.23
  Độ tuổi    55-64     636      30.35       102       21.57       761        4.73

Business Insight (Q3A)
  - H1 được ủng hộ: ở cả 8 nhóm có đủ dữ liệu ở cả 3 vùng (nữ, nam, Blue, Silver và 4 nhóm tuổi từ
    18-34 đến 55-64), churn đều giảm theo thứ tự Z1 > Z2 > Z3. Vậy kết luận của Q2 không do một
    nhóm khách chi phối.
  - H2 bị bác bỏ: độ lớn khác nhau rất nhiều. Ở Z1 churn dao động từ 22,27% (18-34 tuổi) đến
    49,83% (nữ); ở Z3 từ 2,42% (nữ) đến 9,40% (18-34 tuổi). Một ngưỡng chung cho mọi khách sẽ
    cảnh báo lệch: quá nhạy với nhóm này, bỏ sót nhóm khác.
  - Ngay cả ở vùng "an toàn" Z3 vẫn có nhóm churn cao bất thường: Blue 3,37% (khoảng tin cậy 95%:
    2,9-3,8%), Silver 8,08% (5,4-10,8%), Gold 13,83% (6,9-20,8%); và nhóm 18-34 tuổi 9,40%
    (6,6-12,2%) so với 3,42% và 3,23% ở hai nhóm 35-44, 45-54. Các khoảng tin cậy không chồng
    lên nhau nên đây không phải nhiễu ngẫu nhiên. (Khoảng tin cậy = p +/- 1,96 x căn[p(1-p)/n],
    có thể tự tính lại từ N và churn trong bảng.) Dữ liệu không có biến để giải thích (phí thường
    niên, ưu đãi ...), nên chỉ ghi nhận như điểm cần theo dõi, không suy diễn nguyên nhân.
  - HAVING loại các ô dưới 50 khách: nhóm 65+ tuổi (111 khách) và Platinum (20 khách) không xuất
    hiện trong bảng, Gold chỉ còn vùng Z3 (ở Z1 và Z2 Gold chỉ có 17 và 5 khách).
*/


/* ----------------------------------------------------------------------------
   Q3B — CHÊNH LỆCH NỮ - NAM CÓ Ý NGHĨA THỐNG KÊ KHÔNG?  (z-score so sánh hai tỉ lệ)
   z = (p_nữ - p_nam) / căn[ p_gộp x (1 - p_gộp) x (1/n_nữ + 1/n_nam) ]
   ---------------------------------------------------------------------------- */
WITH Cells AS (
    SELECT Trans_Zone,
           Gender,
           COUNT(*)            AS N,
           SUM(Attrition_Flag) AS K          -- số khách rời bỏ
    FROM dbo.vw_Customer_Segments
    GROUP BY Trans_Zone, Gender
),
Paired AS (   -- ghép dòng của nữ với dòng của nam trong cùng một vùng
    SELECT f.Trans_Zone,
           f.N                              AS N_F,
           m.N                              AS N_M,
           1.0 * f.K / f.N                  AS P_F,
           1.0 * m.K / m.N                  AS P_M,
           1.0 * (f.K + m.K) / (f.N + m.N)  AS P_All      -- tỉ lệ gộp hai giới
    FROM Cells AS f
    INNER JOIN Cells AS m
            ON m.Trans_Zone = f.Trans_Zone
    WHERE f.Gender = 'F'
      AND m.Gender = 'M'
)
SELECT Trans_Zone,
       N_F,
       N_M,
       CAST(100 * P_F          AS DECIMAL(5,2)) AS Churn_F_Pct,
       CAST(100 * P_M          AS DECIMAL(5,2)) AS Churn_M_Pct,
       CAST(100 * (P_F - P_M)  AS DECIMAL(5,2)) AS Gap_F_minus_M_pts,
       CAST((P_F - P_M) / SQRT(P_All * (1 - P_All) * (1.0 / N_F + 1.0 / N_M)) AS DECIMAL(6,2)) AS Z_Score
FROM Paired
ORDER BY Trans_Zone;
GO

/*
Kết quả tham chiếu (Q3B)
  Trans_Zone  N_F   N_M   Churn_F_Pct  Churn_M_Pct  Gap_F_minus_M_pts  Z_Score
  Z1          1473  1655     49.83        27.37          22.46           12.92
  Z2           416   503     26.92        18.29           8.63            3.13
  Z3          3469  2611      2.42         5.82          -3.40           -6.79

Business Insight (Q3B)
  - Giới tính là tương tác rõ nhất. Nếu chỉ nhìn gộp, nữ churn 17,36% và nam 14,62% (chênh khoảng
    2,7 điểm %) - dễ bị bỏ qua. Nhưng tách theo vùng giao dịch thì khác hẳn: ở Z1 nữ churn 49,83%
    so với 27,37% của nam (chênh +22,46 điểm %, z = 12,92); ở Z2 chênh +8,63 (z = 3,13); còn ở Z3
    quy luật ĐẢO CHIỀU: nữ 2,42% thấp hơn nam 5,82% (chênh -3,40; z = -6,79).
  - Cách đọc z: |z| > 1,96 là có ý nghĩa ở mức 5% cho MỘT phép so sánh. Vì ở đây có 3 phép so sánh,
    dùng ngưỡng thận trọng hơn |z| > 2,4; cả ba vùng đều vượt, nên chênh lệch không phải ngẫu nhiên.
  - Ý nghĩa: khoảng một nửa số khách nữ ở vùng giao dịch thấp (<= 50 lượt) đã rời bỏ, trong khi
    khách nữ giao dịch nhiều gần như an toàn. Một mô hình không có tương tác giữa giới tính và mức
    giao dịch sẽ mô tả sai cả hai đầu.
  - Đây là phát hiện THĂM DÒ. Dùng giới tính làm căn cứ chăm sóc hay ưu đãi khách hàng cần cân nhắc
    yếu tố công bằng và pháp lý; trong báo cáo nên trình bày như dấu hiệu để mô hình bắt tương tác
    chứ không phải quy tắc kinh doanh. Chênh lệch này có phải do biến khác gây ra không: xem Q3C.
*/


/* ----------------------------------------------------------------------------
   Q3C — KIỂM SOÁT BIẾN GÂY NHIỄU: CHÊNH LỆCH NỮ - NAM CÓ PHẢI DO THU NHẬP?
   So nữ với nam TRONG CÙNG mức thu nhập, chỉ ở vùng Z1 (<= 50 lượt, nơi chênh lệch lớn nhất).
   Ô nào có Num_Z1 dưới 50 thì chỉ để tham khảo, đừng diễn giải.
   ---------------------------------------------------------------------------- */
SELECT Gender,
       Income_Category,
       COUNT(*)                                          AS Num_Customers,
       SUM(CASE WHEN Trans_Zone = 'Z1' THEN 1 ELSE 0 END) AS Num_Z1,
       CAST(100.0 * SUM(CASE WHEN Trans_Zone = 'Z1' THEN Attrition_Flag ELSE 0 END)
                  / NULLIF(SUM(CASE WHEN Trans_Zone = 'Z1' THEN 1 ELSE 0 END), 0)
            AS DECIMAL(5,2))                             AS Churn_Z1_Pct
FROM dbo.vw_Customer_Segments
GROUP BY Gender, Income_Category
ORDER BY Gender, Income_Category;
GO

/*
Kết quả tham chiếu (Q3C)
  Gender  Income_Category  Num_Customers  Num_Z1  Churn_Z1_Pct
  F       $40K - $60K          1014          282       47.16
  F       Less than $40K       3284          907       51.16
  F       Unknown              1060          284       48.24
  M       $120K +               727          258       33.72
  M       $40K - $60K           776          266       24.44
  M       $60K - $80K          1402          482       26.35
  M       $80K - $120K         1535          538       27.88
  M       Less than $40K        277           93       22.58
  M       Unknown                52           18       16.67

Business Insight (Q3C)
  - Phát hiện về cấu trúc dữ liệu: giới tính và thu nhập gần như trùng nhau. Khách nữ chỉ có ở 3
    mức (dưới $40K: 61%, $40K-$60K: 19%, Unknown: 20%) và KHÔNG có khách nữ nào ở các mức từ $60K
    trở lên (bảng không có dòng nào), trong khi 77% khách nam ở các mức từ $60K trở lên. Thêm nữa,
    95% khách 'Unknown' về thu nhập (1.060 / 1.112) là nữ. Cấu trúc này hiếm gặp ở dữ liệu thực,
    có thể do cách thu thập hoặc làm sạch; cần ghi vào phần Hạn chế và dùng biến thu nhập thận trọng.
  - Chênh lệch nữ - nam KHÔNG do thu nhập: ở những mức mà cả hai giới đều có mặt, nữ vẫn churn cao
    hơn hẳn nam ở vùng Z1: $40K-$60K là 47,16% so với 24,44% (282 và 266 khách); dưới $40K là
    51,16% so với 22,58% (907 và 93 khách; nam ít nên kém chắc chắn hơn). Kiểm tra thêm ngoài file
    SQL này (Python) khi tách theo dư nợ xoay vòng, xu hướng Q4/Q1, độ tuổi và hạng thẻ Blue cho
    kết quả cùng hướng, chênh từ 10,5 đến 24,2 điểm %.
  - Bài học phương pháp: đây là cách kiểm soát biến gây nhiễu bằng phân tầng (so sánh trong cùng
    một mức thu nhập). Nó chỉ làm được ở vùng hai nhóm cùng có mặt; muốn kiểm soát nhiều biến cùng
    lúc cần mô hình (phần ML).
*/


/* ============================================================================
   Q4 — ĐIỂM RỦI RO VÀ DANH SÁCH CẢNH BÁO (WATCH-LIST)
   Business Question:
   "Danh sách khách cần đội Retention can thiệp trước gồm những ai, và đáng tin đến đâu?
    Từng tín hiệu mạnh yếu thế nào, và khi gộp lại thì bắt được bao nhiêu khách rời bỏ?"

   Phương pháp: mỗi khách nhận 6 "cờ cảnh báo" (1 = có, 0 = không). Risk_Score = tổng số cờ (0-6).
   Cộng điểm với trọng số bằng nhau là lựa chọn có chủ ý: đơn giản, minh bạch, nhân viên chăm sóc
   khách hàng hiểu ngay. Điểm này đóng vai trò đường cơ sở (baseline) để so với mô hình ở phần ML.
     F1 Giao dịch thấp         Total_Trans_Ct         <= 60   (khoảng 5 lượt/tháng)
     F2 Giao dịch sụt mạnh     Total_Ct_Chng_Q4_Q1    <  0.5  (số lượt Q4 chưa bằng nửa Q1)
     F3 Dư nợ xoay vòng thấp   Total_Revolving_Bal    <  500
     F4 Liên hệ CSKH nhiều     Contacts_Count_12_mon  >= 3
     F5 Ngừng hoạt động lâu    Months_Inactive_12_mon >= 3
     F6 Dùng ít sản phẩm       Total_Relationship_Count <= 2
   Các ngưỡng được chọn theo điểm gãy quan sát được trên chính dữ liệu này (Q2 và khảo sát từng
   biến), không tối ưu hóa; xem Hạn chế (2).
   Lưu ý từ Q3: cùng một ngưỡng được áp cho mọi khách, trong khi độ nhạy khác nhau giữa các nhóm
   (vd. nữ ở vùng giao dịch thấp). Risk_Score cố ý KHÔNG dùng giới tính; mô hình ở phần ML có thể
   thêm các tương tác này.

   SQL Techniques: VIEW (viết logic tính điểm một lần, các truy vấn sau dùng lại), CTE,
                   CASE WHEN, CROSS APPLY (VALUES ...), window function tích lũy
                   (SUM() OVER (ORDER BY ...)), TOP + ORDER BY nhiều cột.
   ============================================================================ */

-- Q4-SETUP. View chứa 6 cờ và Risk_Score cho từng khách
CREATE OR ALTER VIEW dbo.vw_Churn_Risk_Score
AS
WITH Flags AS (
    SELECT c.CLIENTNUM,
           c.Attrition_Flag,
           c.Card_Category,
           c.Income_Category,
           a.Total_Trans_Ct,
           a.Total_Trans_Amt,
           a.Total_Ct_Chng_Q4_Q1,
           a.Total_Revolving_Bal,
           a.Contacts_Count_12_mon,
           a.Months_Inactive_12_mon,
           a.Total_Relationship_Count,
           a.Credit_Limit,
           CASE WHEN a.Total_Trans_Ct            <= 60  THEN 1 ELSE 0 END AS Flag_Low_Trans,
           CASE WHEN a.Total_Ct_Chng_Q4_Q1       <  0.5 THEN 1 ELSE 0 END AS Flag_Trans_Drop,
           CASE WHEN a.Total_Revolving_Bal       <  500 THEN 1 ELSE 0 END AS Flag_Low_Revolving,
           CASE WHEN a.Contacts_Count_12_mon     >= 3   THEN 1 ELSE 0 END AS Flag_Many_Contacts,
           CASE WHEN a.Months_Inactive_12_mon    >= 3   THEN 1 ELSE 0 END AS Flag_Inactive,
           CASE WHEN a.Total_Relationship_Count  <= 2   THEN 1 ELSE 0 END AS Flag_Few_Products
    FROM dbo.Customers AS c
    INNER JOIN dbo.Card_Activity AS a
            ON a.CLIENTNUM = c.CLIENTNUM
)
SELECT f.*,
       f.Flag_Low_Trans + f.Flag_Trans_Drop + f.Flag_Low_Revolving
     + f.Flag_Many_Contacts + f.Flag_Inactive + f.Flag_Few_Products AS Risk_Score
FROM Flags AS f;
GO


/* ----------------------------------------------------------------------------
   Q4A — TỪNG TÍN HIỆU RIÊNG LẺ MẠNH YẾU THẾ NÀO?
   (Bôi đen cả khối từ DECLARE đến dấu chấm phẩy cuối cùng rồi F5.)
   ---------------------------------------------------------------------------- */
DECLARE @Total_Attrited INT          = (SELECT SUM(Attrition_Flag) FROM dbo.Customers);
DECLARE @Base_Churn     DECIMAL(9,6) = (SELECT AVG(1.0 * Attrition_Flag) FROM dbo.Customers);

SELECT s.Signal,
       COUNT(*)              AS Num_Flagged,
       SUM(v.Attrition_Flag) AS Num_Attrited,
       CAST(100.0 * SUM(v.Attrition_Flag) / COUNT(*)              AS DECIMAL(5,2)) AS Churn_Rate_Pct,   -- = precision
       CAST(100.0 * SUM(v.Attrition_Flag) / @Total_Attrited       AS DECIMAL(5,2)) AS Recall_Pct,
       CAST(1.0   * SUM(v.Attrition_Flag) / COUNT(*) / @Base_Churn AS DECIMAL(5,2)) AS Lift
FROM dbo.vw_Churn_Risk_Score AS v
CROSS APPLY (VALUES (N'F1 Giao dịch thấp      (Total_Trans_Ct <= 60)',       v.Flag_Low_Trans),
                    (N'F2 Giao dịch sụt mạnh  (Ct_Chng_Q4_Q1 < 0.5)',        v.Flag_Trans_Drop),
                    (N'F3 Dư nợ xoay vòng thấp (Revolving_Bal < 500)',       v.Flag_Low_Revolving),
                    (N'F4 Liên hệ CSKH nhiều  (Contacts >= 3)',              v.Flag_Many_Contacts),
                    (N'F5 Ngừng hoạt động lâu (Months_Inactive >= 3)',       v.Flag_Inactive),
                    (N'F6 Dùng ít sản phẩm    (Relationship_Count <= 2)',    v.Flag_Few_Products)
            ) AS s (Signal, Is_On)
WHERE s.Is_On = 1                       -- chỉ giữ những khách đang "bật" cờ đó
GROUP BY s.Signal
ORDER BY Lift DESC;
GO

/*
Kết quả tham chiếu (Q4A)
  Signal                                    Num_Flagged  Num_Attrited  Churn_Rate_Pct  Recall_Pct  Lift
  F2 Giao dịch sụt mạnh                        1370          697          50.88          42.84      3.17
  F3 Dư nợ xoay vòng thấp                      2595          998          38.46          61.34      2.39
  F1 Giao dịch thấp                            4047         1391          34.37          85.49      2.14
  F6 Dùng ít sản phẩm                          2153          579          26.89          35.59      1.67
  F4 Liên hệ CSKH nhiều                        5002         1109          22.17          68.16      1.38
  F5 Ngừng hoạt động lâu                       4583         1007          21.97          61.89      1.37

Business Insight (Q4A)
  - F2 (số lượt Q4 chưa bằng nửa Q1) là tín hiệu "sắc" nhất: lift 3,17, churn 50,88%, nhưng chỉ
    phủ 42,84% khách rời bỏ. F1 (<= 60 lượt) là tín hiệu "rộng" nhất: phủ 85,49% khách rời bỏ
    nhưng lift chỉ 2,14, vì lẫn nhiều khách ở lại.
  - F3: dư nợ xoay vòng < 500 (gồm 2.470 khách có dư nợ bằng 0) có churn 38,46%, lift 2,39.
  - F4-F6 yếu hơn (lift 1,37-1,67) nhưng đến từ góc nhìn chăm sóc khách hàng (liên hệ nhiều,
    ngừng hoạt động, ít sản phẩm) nên bổ sung thông tin mà các cờ giao dịch không có.
  - Không tín hiệu đơn lẻ nào vừa sắc vừa rộng => gộp lại (Q4B).
*/


/* ----------------------------------------------------------------------------
   Q4B — GỘP 6 TÍN HIỆU: CHURN THEO ĐIỂM RỦI RO, VÀ ĐÁNH ĐỔI GIỮA PRECISION VỚI RECALL
   Các cột cộng dồn trả lời: "Nếu cảnh báo mọi khách có điểm >= Risk_Score này thì ...?"
   ---------------------------------------------------------------------------- */
WITH ByScore AS (
    SELECT Risk_Score,
           COUNT(*)            AS N,
           SUM(Attrition_Flag) AS Attrited
    FROM dbo.vw_Churn_Risk_Score
    GROUP BY Risk_Score
)
SELECT Risk_Score,
       N        AS Num_Customers,
       Attrited AS Num_Attrited,
       CAST(100.0 * Attrited / N AS DECIMAL(5,2))                                          AS Churn_Rate_Pct,
       -- cộng dồn từ điểm cao xuống điểm thấp
       SUM(N) OVER (ORDER BY Risk_Score DESC)                                              AS Cum_Flagged,
       CAST(100.0 * SUM(N) OVER (ORDER BY Risk_Score DESC) / SUM(N) OVER () AS DECIMAL(5,2))
                                                                                           AS Pct_Of_Base,
       CAST(100.0 * SUM(Attrited) OVER (ORDER BY Risk_Score DESC)
                  / SUM(N)        OVER (ORDER BY Risk_Score DESC) AS DECIMAL(5,2))         AS Precision_Pct,
       CAST(100.0 * SUM(Attrited) OVER (ORDER BY Risk_Score DESC)
                  / SUM(Attrited) OVER ()                         AS DECIMAL(5,2))         AS Recall_Pct
FROM ByScore
ORDER BY Risk_Score DESC;
GO

/*
Kết quả tham chiếu (Q4B)
  Risk_Score  Num_Customers  Num_Attrited  Churn_Rate_Pct  Cum_Flagged  Pct_Of_Base  Precision_Pct  Recall_Pct
      6              59            59          100.00           59         0.58         100.00         3.63
      5             295           270           91.53          354         3.50          92.94        20.22
      4             785           545           69.43         1139        11.25          76.73        53.72
      3            1778           451           25.37         2917        28.80          45.42        81.44
      2            3240           246            7.59         6157        60.80          25.52        96.56
      1            2967            52            1.75         9124        90.10          17.79        99.75
      0            1003             4            0.40        10127       100.00          16.07       100.00

Business Insight (Q4B)
  - Churn tăng ĐƠN ĐIỆU theo điểm rủi ro: 0,40% -> 1,75% -> 7,59% -> 25,37% -> 69,43% -> 91,53%
    -> 100%. Gộp tín hiệu hiệu quả hơn hẳn từng cờ riêng lẻ (cờ tốt nhất chỉ đạt churn 50,88%).
  - Hai mốc vận hành để chọn:
      Risk_Score >= 4 : 1.139 khách (11,25% tệp) -> precision 76,73%, recall 53,72%;
      Risk_Score >= 3 : 2.917 khách (28,80% tệp) -> precision 45,42%, recall 81,44%.
    Chọn mốc nào là quyết định vận hành: năng lực của đội Retention (số cuộc gọi mỗi tuần) và chi
    phí ưu đãi so với giá trị giữ chân một khách.
  - So với luật cũ ở bản trước (Total_Trans_Ct < 45 và Months_Inactive >= 3 và Contacts >= 3):
    luật cũ gắn cờ 676 khách, precision 54,88%, recall chỉ 22,80% (bỏ sót hơn 77% khách rời
    bỏ). Mốc >= 4 gắn cờ nhiều hơn 463 khách nhưng bắt được nhiều hơn 503 khách rời bỏ
    (874 so với 371) và precision cao hơn (76,73% so với 54,88%).
  - Cảnh báo trung thực: ngưỡng của 6 cờ được chọn trên chính tập dữ liệu này (chưa tách
    train/test) nên precision/recall ở đây lạc quan hơn so với khi áp dụng cho khách mới;
    xem Hạn chế (2).
*/


/* ----------------------------------------------------------------------------
   Q4C — WATCH-LIST: khách có Risk_Score >= 4, sắp theo mức rủi ro rồi theo giá trị giao dịch
   (TOP 30 để xem mẫu; khi dùng thật hãy bỏ TOP để xuất toàn bộ 1.139 khách mỗi tuần)
   ---------------------------------------------------------------------------- */
SELECT TOP (30)
       v.CLIENTNUM,
       CASE WHEN v.Risk_Score >= 5 THEN N'ĐỎ (5-6)' ELSE N'CAM (4)' END AS Alert_Level,
       v.Risk_Score,
       v.Card_Category,
       v.Income_Category,
       v.Total_Trans_Ct,
       v.Total_Ct_Chng_Q4_Q1,
       v.Total_Revolving_Bal,
       v.Contacts_Count_12_mon,
       v.Months_Inactive_12_mon,
       v.Total_Trans_Amt,
       v.Credit_Limit,
       v.Attrition_Flag AS Actual_Attrited      -- chỉ để đối chiếu lịch sử; khi dùng thật cột này CHƯA biết
FROM dbo.vw_Churn_Risk_Score AS v
WHERE v.Risk_Score >= 4
ORDER BY v.Risk_Score DESC,
         v.Total_Trans_Amt DESC;
GO

/*
Kết quả tham chiếu (toàn bộ watch-list Risk_Score >= 4)
  Mức ĐỎ (5-6 điểm): 354 khách, 329 đã rời bỏ (92.94%)
  Mức CAM (4 điểm) : 785 khách, 545 đã rời bỏ (69.43%)
  Hạng thẻ trong watch-list: Blue 1078 | Silver 49 | Gold 10 | Platinum 2

Business Insight (Q4C)
  - Watch-list gồm 1.139 khách có Risk_Score >= 4: mức ĐỎ 354 khách (churn 92,94%) cần xử lý
    ngay; mức CAM 785 khách (churn 69,43%) xử lý tiếp theo.
  - Về thứ tự ưu tiên: bản trước sắp theo hạng thẻ (Platinum > Gold > Silver > Blue), nhưng trong
    watch-list chỉ có 12 khách Gold/Platinum trên 1.139 khách (Blue chiếm 1.078), nên cách sắp đó
    gần như vô nghĩa. Bản này sắp theo mức rủi ro rồi theo Total_Trans_Amt giảm dần: gọi trước
    những khách rủi ro cao nhất và đang mang lại giá trị giao dịch lớn nhất.
  - Giá trị nghiệp vụ: đội Retention nhận một danh sách có thể xuất mỗi tuần, có mức ưu tiên và các
    chỉ số kèm theo để biết nên nói gì khi liên hệ (giao dịch sụt, dư nợ bằng 0, đã liên hệ CSKH
    nhiều lần ...).
*/


/* ============================================================================
   PHỤ LỤC A — THU NHẬP x HẠNG THẺ: PHÂN KHÚC NÀO GẮN KẾT THẤP NHẤT, VÀ HẠNG THẺ CÓ LIÊN QUAN TỚI CHURN?
   Business Question:
   "Trong các nhóm đủ lớn (>= 50 khách), tổ hợp Thu nhập x Hạng thẻ nào có Total_Trans_Ct trung
    bình thấp nhất? Hạng thẻ cao hơn có đi kèm churn thấp hơn không?"

   Vì sao là phụ lục: ở bước khảo sát, độ chênh churn giữa các nhóm của biến hành vi là 25-43 điểm %
   (Total_Ct_Chng_Q4_Q1, Total_Trans_Ct, Contacts_Count, Total_Revolving_Bal, Months_Inactive),
   còn của thu nhập chỉ 3,9 và hạng thẻ 3,3 điểm % (nhóm từ 100 khách trở lên; số này tính bằng
   Python lúc khảo sát, không có trong file SQL). Nhóm biến nhân khẩu học và hạng thẻ vì vậy có ưu
   tiên thấp, và các câu hỏi chính (Q1-Q4) tập trung vào hành vi.

   SQL Techniques: INNER JOIN, GROUP BY nhiều cột, WHERE và HAVING (khác nhau: WHERE lọc dòng
                   TRƯỚC khi nhóm, HAVING lọc nhóm SAU khi nhóm), AVG/COUNT/SUM, CAST.
   ============================================================================ */

-- A1. Thu nhập x Hạng thẻ (loại 'Unknown'; chỉ giữ nhóm >= 50 khách)
SELECT c.Income_Category,
       c.Card_Category,
       COUNT(*)                                            AS Num_Customers,
       CAST(AVG(1.0 * a.Total_Trans_Ct)  AS DECIMAL(6,1))  AS Avg_Trans_Ct,
       CAST(AVG(1.0 * a.Total_Trans_Amt) AS DECIMAL(10,0)) AS Avg_Trans_Amt,
       CAST(100.0 * SUM(c.Attrition_Flag) / COUNT(*) AS DECIMAL(5,2)) AS Churn_Rate_Pct
FROM dbo.Customers AS c
INNER JOIN dbo.Card_Activity AS a
        ON a.CLIENTNUM = c.CLIENTNUM
WHERE c.Income_Category <> 'Unknown'
GROUP BY c.Income_Category, c.Card_Category
HAVING COUNT(*) >= 50
ORDER BY AVG(1.0 * a.Total_Trans_Ct) ASC;      -- sắp theo giá trị chưa làm tròn để không bị hòa
GO

-- A2. Chỉ theo Hạng thẻ (đủ cả 4 hạng, kèm hạn mức tín dụng để kiểm tra yếu tố gây nhiễu)
SELECT c.Card_Category,
       COUNT(*)                                            AS Num_Customers,
       CAST(AVG(1.0 * a.Total_Trans_Ct)  AS DECIMAL(6,1))  AS Avg_Trans_Ct,
       CAST(AVG(1.0 * a.Total_Trans_Amt) AS DECIMAL(10,0)) AS Avg_Trans_Amt,
       CAST(AVG(a.Credit_Limit)          AS DECIMAL(10,0)) AS Avg_Credit_Limit,
       SUM(c.Attrition_Flag)                               AS Num_Attrited,
       CAST(100.0 * SUM(c.Attrition_Flag) / COUNT(*) AS DECIMAL(5,2)) AS Churn_Rate_Pct
FROM dbo.Customers AS c
INNER JOIN dbo.Card_Activity AS a
        ON a.CLIENTNUM = c.CLIENTNUM
GROUP BY c.Card_Category
ORDER BY CASE c.Card_Category
              WHEN 'Blue'   THEN 1
              WHEN 'Silver' THEN 2
              WHEN 'Gold'   THEN 3
              ELSE               4
         END;
GO

/*
Kết quả tham chiếu (A1)
  Income_Category  Card_Category  Num_Customers  Avg_Trans_Ct  Avg_Trans_Amt  Churn_Rate_Pct
  $80K - $120K     Blue               1395          61.7          4290          15.41
  $120K +          Blue                645          61.8          4200          17.52
  $60K - $80K      Blue               1273          61.9          4202          13.51
  $40K - $60K      Blue               1675          64.2          4255          15.34
  Less than $40K   Blue               3403          65.6          4234          17.22
  $80K - $120K     Silver              117          72.2          6520          18.80
  $120K +          Silver               60          73.3          6291          18.33
  $40K - $60K      Silver               99          73.3          5971          11.11
  $60K - $80K      Silver               96          74.8          6479          11.46
  Less than $40K   Silver              130          77.4          7135          15.38

Kết quả tham chiếu (A2)
  Card_Category  Num_Customers  Avg_Trans_Ct  Avg_Trans_Amt  Avg_Credit_Limit  Num_Attrited  Churn_Rate_Pct
  Blue               9436          64.0          4225            7364             1519          16.10
  Silver              555          74.7          6590           25278               82          14.77
  Gold                116          81.5          7686           28416               21          18.10
  Platinum             20          87.0          9000           30283                5          25.00

Business Insight (Phụ lục A)
  - Nhóm gắn kết thấp nhất là Blue thu nhập trung-cao: $80K-$120K (61,7 lượt), $120K+ (61,8)
    và $60K-$80K (61,9). Nhưng chênh lệch giữa các nhóm Blue rất nhỏ (tối đa 3,9 lượt).
  - Thu nhập cao KHÔNG đồng nghĩa dùng thẻ nhiều: nhóm thu nhập dưới $40K có Avg_Trans_Ct cao
    nhất ở cả hai hạng thẻ (65,6 ở Blue; 77,4 ở Silver). Lưu ý: nhóm dưới $40K có khoảng 92% là
    khách nữ (Q3C), nên kết quả này lẫn hiệu ứng giới tính; mọi so sánh theo thu nhập ở phụ lục
    này đều chịu ảnh hưởng đó.
  - Khoảng cách giữa hai hạng thẻ (Silver hơn Blue khoảng 10,7 lượt: 74,7 so với 64,0) lớn gấp
    2-3 lần khoảng cách giữa các mức thu nhập trong cùng một hạng thẻ (3,9 lượt ở Blue; 5,2
    lượt ở Silver). Vậy hạng thẻ liên hệ với mức gắn kết mạnh hơn thu nhập.
  - NHƯNG gắn kết cao hơn không đi kèm churn thấp hơn đáng kể: Silver 14,77% so với Blue 16,10%.
    Chênh 1,33 điểm % nhỏ hơn một sai số chuẩn (khoảng 1,55 điểm %), tức không thể kết luận
    Silver giữ chân tốt hơn. Với các nhóm khoảng 100 khách, sai số chuẩn của churn khoảng
    3,6 điểm %, nên đừng diễn giải chênh lệch giữa từng nhóm Silver nhỏ (11,11% - 18,80%).
  - Silver có hạn mức tín dụng trung bình gấp 3,4 lần Blue (25.278 so với 7.364) và chi tiêu
    cao hơn 56% (6.590 so với 4.225): đây là nhóm khách khác biệt về năng lực tài chính ngay từ
    đầu (thiên lệch chọn mẫu), nên chênh lệch gắn kết không thể quy cho hạng thẻ.
  - Gold (churn 18,10%, 116 khách) và Platinum (25,00%, chỉ 5/20 khách) quá nhỏ để kết luận;
    HAVING >= 50 loại hết các tổ hợp Gold/Platinum x thu nhập (mỗi tổ hợp tối đa 29 khách).
    Khách 'Unknown' về thu nhập (1.112 khách) bị loại ở A1 bằng WHERE.
  => Dữ liệu KHÔNG ủng hộ khuyến nghị "nâng hạng thẻ để giảm churn" của bản trước. Muốn biết ưu
     đãi nâng hạng có hiệu quả hay không phải thử nghiệm có nhóm đối chứng (A/B test).
*/


/* ============================================================================
   TỔNG HỢP VÀ HẠN CHẾ (đưa thẳng vào báo cáo)
   ============================================================================

   PHÁT HIỆN CHÍNH
     1. Khách rời bỏ giao dịch ít hơn khoảng 35% (44,93 so với 68,67 lượt/năm) và đã giảm dùng
        thẻ từ trước (Q4/Q1 = 0,55 so với 0,74).                                      [Q1]
     2. Quan hệ giữa Total_Trans_Ct và churn là PHI TUYẾN: đỉnh 48,40% ở dải 41-50 lượt; từ 61
        lượt trở lên churn chỉ 3,88%.                                                 [Q2]
     3. Chiều hướng "ít giao dịch -> churn cao" đúng ở cả 8 nhóm khách có đủ dữ liệu, nhưng độ lớn
        khác nhau nhiều và có TƯƠNG TÁC: ở vùng <= 50 lượt, nữ churn 49,83% (nam 27,37%) nhưng ở
        vùng >= 61 lượt nữ lại thấp hơn nam (2,42% so với 5,82%); thẻ Silver/Gold và khách 18-34
        tuổi vẫn churn cao hơn ở vùng "an toàn".                                      [Q3]
     4. Gộp 6 tín hiệu cho churn tăng đơn điệu từ 0,40% đến 100%. Mốc Risk_Score >= 4 đạt
        precision 76,73% và recall 53,72%, vượt hẳn luật 3 điều kiện cũ (54,88% / 22,80%). [Q4]
     5. Thu nhập và hạng thẻ không phải đòn bẩy giảm churn rõ ràng trong dữ liệu này.     [Phụ lục A]

   HẠN CHẾ (cần nêu trong báo cáo)
     (1) Ảnh chụp, không có trục thời gian. Total_Trans_Ct, Total_Trans_Amt, Total_Ct_Chng_Q4_Q1
         được đo trong chính 12 tháng mà việc rời bỏ xảy ra; khách đang rời đi thì tự nhiên giao
         dịch ít đi. Do đó đây là dấu hiệu ĐỒNG THỜI, chưa phải "chỉ báo sớm" đã được chứng minh.
         Muốn kết luận dự báo sớm cần dữ liệu đo hành vi TRƯỚC thời điểm rời bỏ.
     (2) Ngưỡng chọn trên chính dữ liệu này (60 lượt, 0,5; 500; 3; 3; 2). Precision/recall của
         Risk_Score vì vậy mang tính mô tả và lạc quan; cần kiểm chứng trên tập test độc lập
         (hoặc cross-validation) ở phần mô hình.
     (3) Tương quan không phải nhân quả. Các so sánh theo hạng thẻ, thu nhập chỉ cho thấy mối liên
         hệ; kết luận về tác động của can thiệp (nâng hạng, ưu đãi) cần thử nghiệm A/B.
     (4) Một số nhóm nhỏ (Gold 116 khách, Platinum 20 khách, các nhóm khoảng 100 khách ở Phụ lục A1) có
         sai số ngẫu nhiên lớn.
     (5) Dữ liệu thiếu và mất cân bằng: 'Unknown' ở 3 cột phân loại (7,4% - 15,0%), và churn chỉ
         16,07%.
     (6) Phân tầng mang tính thăm dò (Q3): xét nhiều ô và nhiều cách chia nhóm. Các chênh lệch lớn
         (|z| từ 3 trở lên, khoảng tin cậy không chồng lấn) đủ chắc để ghi nhận, nhưng chưa kiểm
         soát đồng thời mọi biến; cần mô hình ở phần ML. Thu nhập và giới tính gần như trùng nhau
         (không có khách nữ từ $60K trở lên; 95% khách Unknown về thu nhập là nữ) nên hiệu ứng của
         hai biến này khó tách bạch.

   CẦU NỐI SANG PHẦN MÔ HÌNH
     - Biến ứng viên mạnh: Total_Trans_Ct, Total_Ct_Chng_Q4_Q1, Total_Revolving_Bal,
       Contacts_Count_12_mon, Months_Inactive_12_mon, Total_Relationship_Count.
     - Thêm Gender, Age và tương tác Gender x mức giao dịch làm đặc trưng, hoặc dùng mô hình cây tự
       bắt tương tác; kiểm tra tính công bằng giữa hai giới trước khi triển khai (Q3B).
     - Dùng mô hình phi tuyến (cây quyết định / random forest / gradient boosting) cùng baseline
       hồi quy logistic và baseline "Risk_Score >= 4" của file này để so sánh.
     - Chia train/test phân tầng theo Attrition_Flag; đánh giá bằng precision, recall, PR-AUC.
     - Nếu mục tiêu là dự báo SỚM, cân nhắc loại hoặc xử lý riêng các biến đo trong giai đoạn rời
       bỏ (xem Hạn chế 1).
   ============================================================================ */
