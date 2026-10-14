# Báo Cáo Tóm Tắt Kết Quả Khai Phá Dữ Liệu Bằng T-SQL (SQL Phase Summary)

**Đề tài:** Phân tích và Dự đoán Rủi ro Rời bỏ Dịch vụ Thẻ Tín dụng (Credit Card Customer Churn Analysis)  
**Môn học:** ADY201m - Advanced Data Analytics  
**Giai đoạn hoàn thành:** Data Cleaning & T-SQL Data Exploration (Hoàn tất giai đoạn SQL)

---

## 1. Mục tiêu và Kiến trúc Cơ sở Dữ liệu

Giai đoạn này tập trung chuẩn hóa và nạp dữ liệu vào hệ quản trị cơ sở dữ liệu quan hệ (SQL Server), sau đó thực hiện các truy vấn T-SQL chuyên sâu nhằm khám phá hành vi của khách hàng rời bỏ (*Attrited Customer*) so với khách hàng ở lại (*Existing Customer*).

### Kiến trúc phân tách bảng (Normalized Schema)
Từ dữ liệu sạch `BankChurners_clean.csv`, nhóm đã thiết kế 2 bảng quan hệ:
- **`dbo.Customers` (10.127 bản ghi):** Lưu trữ định danh (`CLIENTNUM` làm khóa chính), thông tin nhân khẩu học (độ tuổi, giới tính, số người phụ thuộc, học vấn, tình trạng hôn nhân, mức thu nhập) và thông tin mở thẻ (`Months_on_book`, `Card_Category`, `Attrition_Flag`).
- **`dbo.Card_Activity` (10.127 bản ghi):** Lưu trữ hành vi sử dụng thẻ (`Activity_ID` là Identity PK, `CLIENTNUM` làm Foreign Key), bao gồm hạn mức tín dụng (`Credit_Limit`), dư nợ (`Total_Revolving_Bal`), số lượng và giá trị giao dịch (`Total_Trans_Ct`, `Total_Trans_Amt`), tỉ lệ biến thiên Q4/Q1, số tháng không hoạt động và số lần liên hệ ngân hàng.

---

## 2. Các Phát hiện Kinh doanh Trọng tâm (Key Insights)

### Q0: Hồ sơ chất lượng dữ liệu & Churn nền
- **Tổng quy mô:** 10.127 khách hàng, trong đó có 1.627 khách hàng rời bỏ dịch vụ.
- **Tỉ lệ rời bỏ nền (Base Churn Rate):** **16,07%** (xấp xỉ 1 rời bỏ : 5 ở lại). Đây là bài toán dữ liệu mất cân bằng (imbalanced classification).
- **Giá trị 'Unknown':** Chiếm 15,00% ở học vấn, 10,98% ở thu nhập và 7,40% ở tình trạng hôn nhân. Tỉ lệ rời bỏ ở nhóm 'Unknown' xấp xỉ mức nền (16,8% - 17,2%), do đó nhóm quyết định giữ nguyên nhãn này thay vì loại bỏ hay điền khuyết tùy tiện.

### Q1: Hành vi giao dịch giữa nhóm Churn và Non-Churn
- Khách hàng rời bỏ có tần suất giao dịch trung bình thấp hơn **~35%** so với khách hàng ở lại (**44,93** lượt/năm so với **68,67** lượt/năm).
- Tỉ lệ thay đổi số lượng giao dịch quý 4 so với quý 1 (`Total_Ct_Chng_Q4_Q1`) ở nhóm rời bỏ sụt giảm mạnh (trung bình **0,55** so với **0,74** ở nhóm duy trì), chứng minh khách hàng có xu hướng giảm tương tác rõ rệt trước khi đóng thẻ.

### Q2: Mối quan hệ phi tuyến tính của `Total_Trans_Ct`
- Tỉ lệ rời bỏ đạt đỉnh **48,40%** ở dải khách hàng thực hiện từ **41 đến 50 giao dịch/năm**.
- Ngược lại, đối với khách hàng thực hiện từ **61 giao dịch trở lên**, tỉ lệ rời bỏ giảm xuống chỉ còn **3,88%**. Đây là ngưỡng an toàn then chốt cho các chương trình kích hoạt giao dịch.

### Q3: Tính bền vững và Hiệu ứng tương tác (Interaction Effects)
- Xu hướng "ít giao dịch $\rightarrow$ churn cao" nhất quán trên mọi phân khúc nhân khẩu học.
- Tuy nhiên, tồn tại tương tác giới tính: ở nhóm $\le 50$ giao dịch, khách hàng nữ có churn rate lên đến **49,83%** (so với nam là **27,37%**). Ở nhóm $\ge 61$ giao dịch, nữ lại có xu hướng gắn bó bền vững hơn nam (**2,42%** so với **5,82%**).

### Q4: Hệ thống chấm điểm rủi ro (Risk Scoring Engine)
Nhóm đã xây dựng quy tắc đánh giá rủi ro đa biến `Risk_Score` kết hợp 6 yếu tố:
1. `Total_Trans_Ct` $\le 60$
2. `Total_Ct_Chng_Q4_Q1` $\le 0,5$
3. `Total_Revolving_Bal` $\le 500$
4. `Contacts_Count_12_mon` $\ge 3$
5. `Months_Inactive_12_mon` $\ge 3$
6. `Total_Relationship_Count` $\le 2$

**Hiệu năng phân loại:**
- Khi áp dụng ngưỡng cảnh báo `Risk_Score >= 4`, mô hình đạt **Precision 76,73%**, **Recall 53,72%** và **Lift = 4,77** (khả năng phát hiện khách rời bỏ cao gấp gần 4,8 lần so với chọn ngẫu nhiên).

---

## 3. Hạn chế và Định hướng cho Giai đoạn Tiếp theo (Machine Learning)

1. **Bản chất dữ liệu cắt ngang (Cross-sectional):** Các chỉ số đo lường trong 12 tháng đồng thời với thời điểm ghi nhận rời bỏ.
2. **Kế hoạch giai đoạn tiếp theo (Python ML):**
   - Sử dụng các thuật toán học máy phân loại phi tuyến: Random Forest, XGBoost, LightGBM.
   - Đánh giá mô hình dựa trên Precision, Recall, F1-Score và PR-AUC (thay vì chỉ dựa vào Accuracy).
   - Xây dựng chiến lược can thiệp sớm (Early Retention Campaigns) dựa trên danh sách cảnh báo rủi ro cao.
